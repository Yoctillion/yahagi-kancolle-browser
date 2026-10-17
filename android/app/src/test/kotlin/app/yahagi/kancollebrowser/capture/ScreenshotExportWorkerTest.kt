package app.yahagi.kancollebrowser.capture

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class ScreenshotExportWorkerTest {
    private val main = LinkedBlockingQueue<Runnable>()

    @Test
    fun successfulOutputSurvivesCloseBeforeWorkerRetiresAndLateGalleryScan() {
        val releaseDispatch = CountDownLatch(1)
        val retired = CountDownLatch(1)
        val cancelled = AtomicReference<() -> Boolean>()
        val scan = AtomicReference<ScreenshotScanCleanup<String>>()
        val deleted = AtomicInteger()
        val worker = ScreenshotExportWorker(dispatchMain = {
            main.offer(it)
            check(releaseDispatch.await(5, TimeUnit.SECONDS))
            retired.countDown()
            true
        })
        try {
            worker.submit(work = { isCancelled ->
                cancelled.set(isCancelled)
                val cleanup = ScreenshotScanCleanup<String> { deleted.incrementAndGet() }
                scan.set(cleanup)
                ScreenshotExport("saved", cleanup::discard)
            }, release = {}) { true }
            main.poll(5, TimeUnit.SECONDS)!!.run()
            worker.close()
            assertTrue("Force the successful job to remain registered during close", cancelled.get()())
            scan.get().onScanned("content://saved")
            assertEquals("A delivered gallery image belongs to the user", 0, deleted.get())
        } finally {
            releaseDispatch.countDown()
            worker.close()
            assertTrue(retired.await(5, TimeUnit.SECONDS))
        }
    }

    @Test
    fun discardedGalleryEntryIsDeletedWhenScanCompletesLater() {
        val deleted = mutableListOf<String>()
        val cleanup = ScreenshotScanCleanup<String>(deleted::add)
        cleanup.discard()
        cleanup.onScanned("content://cancelled")
        assertEquals(listOf("content://cancelled"), deleted)
    }

    @Test
    fun scannedGalleryEntryIsDeletedWhenOutputIsDiscardedLater() {
        val deleted = mutableListOf<String>()
        val cleanup = ScreenshotScanCleanup<String>(deleted::add)
        cleanup.onScanned("content://cancelled")
        assertTrue(deleted.isEmpty())
        cleanup.discard()
        assertEquals(listOf("content://cancelled"), deleted)
    }

    @Test
    fun encodingAndReleaseRunOffCallerAndResultRunsOnlyOnMainDispatcher() {
        val caller = Thread.currentThread()
        val encodingThread = AtomicReference<Thread>()
        val releaseThread = AtomicReference<Thread>()
        val completed = AtomicInteger()
        val bytes = byteArrayOf(1, 2, 3)
        val worker = ScreenshotExportWorker(dispatchMain = { main.offer(it) })
        try {
            worker.submit(work = {
                encodingThread.set(Thread.currentThread())
                ScreenshotExport(bytes)
            }, release = { releaseThread.set(Thread.currentThread()) }) {
                assertSame(caller, Thread.currentThread())
                assertArrayEquals(bytes, it.getOrThrow().value as ByteArray)
                completed.incrementAndGet()
                true
            }
            val callback = main.poll(5, TimeUnit.SECONDS)
            assertNotNull(callback)
            assertNotSame("Encoding must leave the Android caller thread", caller, encodingThread.get())
            assertSame(encodingThread.get(), releaseThread.get())
            assertEquals(0, completed.get())
            callback!!.run()
            assertEquals(1, completed.get())
        } finally { worker.close() }
    }

    @Test
    fun slowEncodingLeavesCallerResponsiveAndCloseDoesNotRecycleItsInputEarly() {
        val entered = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val released = CountDownLatch(1)
        val discarded = CountDownLatch(1)
        val callbacks = AtomicInteger()
        val worker = ScreenshotExportWorker(dispatchMain = { main.offer(it) })
        try {
            worker.submit(work = {
                entered.countDown()
                check(finish.await(5, TimeUnit.SECONDS))
                ScreenshotExport("gallery", discard = { discarded.countDown() })
            }, release = { released.countDown() }) { callbacks.incrementAndGet(); true }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            main.offer(Runnable { callbacks.incrementAndGet() })
            main.remove().run()
            worker.close()
            assertEquals(1L, released.count)
            finish.countDown()
            assertTrue(released.await(5, TimeUnit.SECONDS))
            assertTrue(discarded.await(5, TimeUnit.SECONDS))
            assertEquals(1, callbacks.get())
        } finally { finish.countDown(); worker.close() }
    }

    @Test
    fun latePostedResultIsDiscardedOffMainAfterClose() {
        val discarded = CountDownLatch(1)
        val discardThread = AtomicReference<Thread>()
        val callbacks = AtomicInteger()
        val releases = AtomicInteger()
        val worker = ScreenshotExportWorker(dispatchMain = { main.offer(it) })
        worker.submit(work = {
            ScreenshotExport("gallery", discard = {
                discardThread.set(Thread.currentThread())
                discarded.countDown()
            })
        }, release = { releases.incrementAndGet() }) { callbacks.incrementAndGet(); true }
        val late = main.poll(5, TimeUnit.SECONDS)!!
        worker.close()
        assertTrue(discarded.await(5, TimeUnit.SECONDS))
        late.run()
        assertNotSame(Thread.currentThread(), discardThread.get())
        assertEquals(1, releases.get())
        assertEquals(0, callbacks.get())
    }

    @Test
    fun boundedQueueRejectsExtraWorkAndClosingReleasesQueuedInputs() {
        val entered = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val firstReleased = CountDownLatch(1)
        val secondReleased = CountDownLatch(1)
        val thirdReleased = AtomicInteger()
        val queuedWork = AtomicInteger()
        val rejection = AtomicInteger()
        val worker = ScreenshotExportWorker(dispatchMain = { main.offer(it) })
        try {
            worker.submit(work = {
                entered.countDown(); check(finish.await(5, TimeUnit.SECONDS)); ScreenshotExport("first")
            }, release = { firstReleased.countDown() }) { fail("Cancelled first job completed"); true }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            worker.submit(work = { queuedWork.incrementAndGet(); ScreenshotExport("second") },
                release = { secondReleased.countDown() }) { fail("Cancelled queued job completed"); true }
            worker.submit(work = { fail("Rejected job ran"); ScreenshotExport("third") },
                release = { thirdReleased.incrementAndGet() }) {
                assertTrue(it.isFailure); rejection.incrementAndGet(); true
            }
            assertEquals(1, thirdReleased.get())
            assertEquals(1, rejection.get())
            worker.close()
            finish.countDown()
            assertTrue(firstReleased.await(5, TimeUnit.SECONDS))
            assertTrue(secondReleased.await(5, TimeUnit.SECONDS))
            assertEquals(0, queuedWork.get())
        } finally { finish.countDown(); worker.close() }
    }

    @Test
    fun dispatcherRejectionDiscardsSavedOutputAndRecyclesInput() {
        val discarded = CountDownLatch(1)
        val released = AtomicInteger()
        val callbacks = AtomicInteger()
        val worker = ScreenshotExportWorker(dispatchMain = { false })
        try {
            worker.submit(work = { ScreenshotExport("gallery", discard = { discarded.countDown() }) },
                release = { released.incrementAndGet() }) { callbacks.incrementAndGet(); true }
            assertTrue(discarded.await(5, TimeUnit.SECONDS))
            assertEquals(1, released.get())
            assertEquals(0, callbacks.get())
        } finally { worker.close() }
    }

    @Test
    fun failedEncodingReleasesInputAndReportsFailureOnce() {
        val releases = AtomicInteger()
        val callbacks = AtomicInteger()
        val worker = ScreenshotExportWorker(dispatchMain = { main.offer(it) })
        try {
            worker.submit(work = { throw IllegalStateException("write failed") },
                release = { releases.incrementAndGet() }) {
                assertEquals("write failed", it.exceptionOrNull()?.message)
                callbacks.incrementAndGet(); true
            }
            main.poll(5, TimeUnit.SECONDS)!!.run()
            assertEquals(1, releases.get())
            assertEquals(1, callbacks.get())
        } finally { worker.close() }
    }

    @Test
    fun completionIsClaimedOnceEvenIfDispatcherRepeatsTheCallback() {
        val callbacks = AtomicInteger()
        val worker = ScreenshotExportWorker(dispatchMain = { main.offer(it) })
        try {
            worker.submit(work = { ScreenshotExport("preview") }, release = {}) {
                callbacks.incrementAndGet(); true
            }
            val completion = main.poll(5, TimeUnit.SECONDS)!!
            completion.run()
            completion.run()
            assertEquals(1, callbacks.get())
        } finally { worker.close() }
    }

    @Test
    fun submittingAfterCloseReleasesInputAndReportsRejectionOnCaller() {
        val releases = AtomicInteger()
        val callbacks = AtomicInteger()
        val caller = Thread.currentThread()
        val worker = ScreenshotExportWorker(dispatchMain = { main.offer(it) })
        worker.close()
        worker.submit(work = { fail("Closed worker ran"); ScreenshotExport("unused") },
            release = { releases.incrementAndGet() }) {
            assertSame(caller, Thread.currentThread())
            assertTrue(it.isFailure)
            callbacks.incrementAndGet(); true
        }
        assertEquals(1, releases.get())
        assertEquals(1, callbacks.get())
    }

    @Test
    fun partialWriteFailureDiscardsArtifactAndPreservesOriginalError() {
        val written = StringBuilder()
        val original = IllegalStateException("provider write failed")
        val error = assertThrows(IllegalStateException::class.java) {
            writeScreenshotExport("gallery", discard = { written.clear() }) {
                written.append("partial PNG")
                throw original
            }
        }
        assertSame(original, error)
        assertEquals("", written.toString())
    }

    @Test
    fun cleanupFailureDoesNotReplaceTheWriteFailure() {
        val original = IllegalStateException("provider write failed")
        val cleanup = IllegalArgumentException("provider delete failed")
        val error = assertThrows(IllegalStateException::class.java) {
            writeScreenshotExport("gallery", discard = { throw cleanup }) { throw original }
        }
        assertSame(original, error)
        assertArrayEquals(arrayOf(cleanup), error.suppressed)
    }

    @Test
    fun throwingDispatcherStillDiscardsTheArtifactOffMain() {
        val discarded = CountDownLatch(1)
        val reported = AtomicInteger()
        val worker = ScreenshotExportWorker(
            dispatchMain = { throw IllegalStateException("looper gone") },
            reportFailure = { reported.incrementAndGet() },
        )
        try {
            worker.submit(work = { ScreenshotExport("gallery", discard = { discarded.countDown() }) },
                release = {}) { fail("Unavailable dispatcher completed"); true }
            assertTrue(discarded.await(5, TimeUnit.SECONDS))
            assertEquals(1, reported.get())
        } finally { worker.close() }
    }

    @Test
    fun providerCleanupFailureIsReportedWithoutEscapingWorker() {
        val reported = CountDownLatch(1)
        val worker = ScreenshotExportWorker(dispatchMain = { false }, reportFailure = { reported.countDown() })
        try {
            worker.submit(work = { ScreenshotExport("gallery", discard = { throw IllegalStateException("provider gone") }) },
                release = {}) { fail("Unavailable dispatcher completed"); true }
            assertTrue(reported.await(5, TimeUnit.SECONDS))
        } finally { worker.close() }
    }
}
