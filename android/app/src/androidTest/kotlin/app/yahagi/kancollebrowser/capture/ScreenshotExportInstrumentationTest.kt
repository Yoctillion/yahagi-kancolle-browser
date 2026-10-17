package app.yahagi.kancollebrowser.capture

import android.content.ContentUris
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.yahagi.kancollebrowser.MainActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises only the export tail; no Activity lifecycle, WebView or game navigation is started. */
@RunWith(AndroidJUnit4::class)
class ScreenshotExportInstrumentationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test
    fun activityPreviewReturnsLosslessPngOnMainAndRecyclesInput() {
        val activity = activityWithoutLifecycle()
        val bitmap = pattern()
        try {
            val result = export(activity, bitmap, ScreenshotOutput.MEMORY_PREVIEW)
            result.awaitSuccess()
            val bytes = result.value as ByteArray
            val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            assertNotNull(decoded)
            try { assertPattern(decoded!!) } finally { decoded?.recycle() }
            assertTrue(bitmap.isRecycled)
            assertPendingCleared(activity)
            assertEquals(1, result.calls.get())
        } finally { close(activity) }
    }

    @Test
    fun activityGalleryPublishesReadablePngAndOnlyItsOwnEntryIsRemoved() {
        assumeTrue(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
        val activity = activityWithoutLifecycle()
        val bitmap = pattern()
        var outputUri: android.net.Uri? = null
        try {
            val result = export(activity, bitmap, ScreenshotOutput.GALLERY)
            result.awaitSuccess()
            val fileName = (result.value as String).substringAfterLast('/')
            val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            context.contentResolver.query(
                collection,
                arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.MIME_TYPE,
                    MediaStore.Images.Media.IS_PENDING, MediaStore.Images.Media.RELATIVE_PATH),
                "${MediaStore.Images.Media.DISPLAY_NAME} = ?", arrayOf(fileName), null,
            )!!.use { cursor ->
                assertTrue("Saved gallery entry must be visible", cursor.moveToFirst())
                outputUri = ContentUris.withAppendedId(collection, cursor.getLong(0))
                assertEquals("image/png", cursor.getString(1))
                assertEquals(0, cursor.getInt(2))
                assertEquals("Pictures/Yahagi", cursor.getString(3).trimEnd('/'))
                assertFalse("The test filename must identify one output", cursor.moveToNext())
            }
            val decoded = context.contentResolver.openInputStream(outputUri!!)!!.use {
                BitmapFactory.decodeStream(it)
            }
            assertNotNull(decoded)
            try { assertPattern(decoded!!) } finally { decoded?.recycle() }
            assertTrue(bitmap.isRecycled)
            assertPendingCleared(activity)
            assertEquals(1, result.calls.get())
        } finally {
            close(activity)
            outputUri?.let { context.contentResolver.delete(it, null, null) }
        }
    }

    @Test
    fun activityEncodingFailureClearsPendingAndNextPreviewStillWorks() {
        val activity = activityWithoutLifecycle()
        val invalid = pattern().apply { recycle() }
        try {
            val failed = export(activity, invalid, ScreenshotOutput.MEMORY_PREVIEW)
            failed.awaitResult()
            assertEquals("screenshot_failed", failed.error)
            assertEquals(1, failed.calls.get())
            assertPendingCleared(activity)
            val next = pattern()
            export(activity, next, ScreenshotOutput.MEMORY_PREVIEW).awaitSuccess()
            assertTrue(next.isRecycled)
            assertPendingCleared(activity)
        } finally { close(activity) }
    }

    @Test
    fun activityRejectedSubmissionRecyclesBitmapAndCompletesOnce() {
        val activity = activityWithoutLifecycle()
        close(activity)
        val bitmap = pattern()
        val result = export(activity, bitmap, ScreenshotOutput.MEMORY_PREVIEW)
        result.awaitResult()
        assertEquals("screenshot_failed", result.error)
        assertTrue(bitmap.isRecycled)
        assertEquals(1, result.calls.get())
        assertPendingCleared(activity)
    }

    @Test
    fun mainHeartbeatRunsDuringWorkerWorkAndCloseWaitsForRealBitmapOwnership() {
        val entered = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val released = CountDownLatch(1)
        val discarded = CountDownLatch(1)
        val heartbeat = CountDownLatch(1)
        val callbacks = AtomicInteger()
        val bitmap = pattern()
        val handler = Handler(Looper.getMainLooper())
        val worker = ScreenshotExportWorker(dispatchMain = handler::post)
        try {
            instrumentation.runOnMainSync {
                worker.submit(work = {
                    assertNotSame(Looper.getMainLooper(), Looper.myLooper())
                    entered.countDown()
                    check(finish.await(10, TimeUnit.SECONDS))
                    val bytes = ByteArrayOutputStream().use { stream ->
                        check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream))
                        stream.toByteArray()
                    }
                    ScreenshotExport(bytes, discarded::countDown)
                }, release = { bitmap.recycle(); released.countDown() }) {
                    callbacks.incrementAndGet(); true
                }
            }
            assertTrue(entered.await(10, TimeUnit.SECONDS))
            handler.post { heartbeat.countDown() }
            assertTrue("UI heartbeat must run while export work is pending", heartbeat.await(10, TimeUnit.SECONDS))
            instrumentation.runOnMainSync { worker.close() }
            assertFalse("Close must not recycle a bitmap still owned by work", bitmap.isRecycled)
            finish.countDown()
            assertTrue(released.await(10, TimeUnit.SECONDS))
            assertTrue(discarded.await(10, TimeUnit.SECONDS))
            assertTrue(bitmap.isRecycled)
            instrumentation.waitForIdleSync()
            assertEquals(0, callbacks.get())
        } finally {
            finish.countDown()
            instrumentation.runOnMainSync { worker.close() }
        }
    }

    private fun activityWithoutLifecycle(): MainActivity {
        lateinit var activity: MainActivity
        instrumentation.runOnMainSync {
            activity = MainActivity()
            ContextWrapper::class.java.getDeclaredMethod("attachBaseContext", Context::class.java).apply {
                isAccessible = true
            }.invoke(activity, context)
        }
        return activity
    }

    private fun export(activity: MainActivity, bitmap: Bitmap, output: ScreenshotOutput): Reply {
        val reply = Reply()
        instrumentation.runOnMainSync {
            field("activeScreenshotResult").set(activity, reply)
            field("activeScreenshotOutput").set(activity, output)
            MainActivity::class.java.getDeclaredMethod(
                "finishScreenshot", Bitmap::class.java, MethodChannel.Result::class.java,
            ).apply { isAccessible = true }.invoke(activity, bitmap, reply)
        }
        return reply
    }

    private fun close(activity: MainActivity) {
        instrumentation.runOnMainSync {
            (field("screenshotExportWorker").get(activity) as ScreenshotExportWorker).close()
        }
    }

    private fun assertPendingCleared(activity: MainActivity) {
        instrumentation.runOnMainSync {
            assertNull(field("activeScreenshotResult").get(activity))
            assertNull(field("activeScreenshotOutput").get(activity))
        }
    }

    private fun field(name: String) = MainActivity::class.java.getDeclaredField(name).apply { isAccessible = true }

    private fun pattern() = Bitmap.createBitmap(31, 19, Bitmap.Config.ARGB_8888).apply {
        eraseColor(Color.RED)
        setPixel(0, 0, Color.GREEN)
        setPixel(30, 18, Color.BLUE)
        setPixel(15, 9, Color.WHITE)
    }

    private fun assertPattern(bitmap: Bitmap) {
        assertEquals(31, bitmap.width)
        assertEquals(19, bitmap.height)
        assertEquals(Color.GREEN, bitmap.getPixel(0, 0))
        assertEquals(Color.BLUE, bitmap.getPixel(30, 18))
        assertEquals(Color.WHITE, bitmap.getPixel(15, 9))
        assertEquals(Color.RED, bitmap.getPixel(4, 5))
    }

    private class Reply : MethodChannel.Result {
        val completed = CountDownLatch(1)
        val calls = AtomicInteger()
        var value: Any? = null
        var error: String? = null
        var onMain = false
        override fun success(result: Any?) { value = result; complete() }
        override fun error(code: String, message: String?, details: Any?) { error = code; complete() }
        override fun notImplemented() { error = "not_implemented"; complete() }
        private fun complete() {
            onMain = Looper.myLooper() === Looper.getMainLooper()
            calls.incrementAndGet()
            completed.countDown()
        }
        fun awaitResult() {
            assertTrue("Screenshot did not complete", completed.await(15, TimeUnit.SECONDS))
            assertTrue("Result must be delivered on the main looper", onMain)
        }
        fun awaitSuccess() { awaitResult(); assertNull(error); assertNotNull(value) }
    }
}
