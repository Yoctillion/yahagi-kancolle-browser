package app.yahagi.kancollebrowser.backup

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.yahagi.kancollebrowser.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BackupSavePickerTest {
    private class Result : MethodChannel.Result {
        private val latch = CountDownLatch(1)
        val replies = AtomicInteger()
        var value: Any? = null
        var errorCode: String? = null
        override fun success(result: Any?) { replies.incrementAndGet(); value = result; latch.countDown() }
        override fun error(code: String, message: String?, details: Any?) {
            replies.incrementAndGet(); errorCode = code; latch.countDown()
        }
        override fun notImplemented() { errorCode = "not_implemented"; latch.countDown() }
        fun await(): Any? {
            assertTrue("MethodChannel result timed out", latch.await(10, TimeUnit.SECONDS))
            return value
        }
        fun repliedWithin(milliseconds: Long) = latch.await(milliseconds, TimeUnit.MILLISECONDS)
    }

    @Test fun completePayloadIsStagedBeforePickerAndCancellationRemovesIt() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val launched = CountDownLatch(1)
            val result = Result()
            lateinit var handler: RecordBackupHandler
            lateinit var store: PendingBackupExportStore
            lateinit var root: File
            val bytes = byteArrayOf(1, 2, 3)
            scenario.onActivity { activity ->
                root = File(activity.filesDir, "export-test-${System.nanoTime()}")
                store = PendingBackupExportStore(root)
                handler = RecordBackupHandler(activity, { intent, code ->
                    assertEquals(Intent.ACTION_CREATE_DOCUMENT, intent.action)
                    assertEquals("backup.yhb", intent.getStringExtra(Intent.EXTRA_TITLE))
                    val entry = store.awaitingPicker()!!
                    assertEquals(entry.requestCode, code)
                    assertArrayEquals(bytes, store.sourceFile(entry.token).readBytes())
                    launched.countDown()
                }, exportStore = store)
                handler.onMethodCall(MethodCall("saveFile", mapOf("name" to "backup.yhb", "bytes" to bytes)), result)
            }
            assertTrue(launched.await(10, TimeUnit.SECONDS))
            val requestCode = store.awaitingPicker()!!.requestCode
            scenario.onActivity {
                handler.onActivityResult(requestCode, Activity.RESULT_CANCELED, null)
            }
            assertNull(result.await())
            assertNull(result.errorCode)
            assertNull(store.awaitingPicker())
            scenario.onActivity { handler.dispose() }
            root.deleteRecursively()
        }
    }

    @Test fun verifiedSaveSurvivesActivityDisposalBeforeDartCompletion() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val launched = CountDownLatch(1)
            val saved = Result()
            lateinit var handler: RecordBackupHandler
            lateinit var file: File
            lateinit var uri: Uri
            lateinit var root: File
            lateinit var store: PendingBackupExportStore
            val bytes = byteArrayOf(1, 2, 3, 4)
            scenario.onActivity { activity ->
                root = File(activity.filesDir, "export-test-${System.nanoTime()}")
                store = PendingBackupExportStore(root)
                file = BackupShareCache.write(File(activity.cacheDir, "record-backup-share"), "save-probe.yhb", byteArrayOf(0))
                uri = FileProvider.getUriForFile(activity, "${activity.packageName}.diagnostics", file)
                handler = RecordBackupHandler(activity, { _, _ -> launched.countDown() }, exportStore = store)
                handler.onMethodCall(MethodCall("saveFile", mapOf("name" to "save-probe.yhb", "bytes" to bytes)), saved)
            }
            assertTrue(launched.await(10, TimeUnit.SECONDS))
            val requestCode = store.awaitingPicker()!!.requestCode
            scenario.onActivity {
                handler.onActivityResult(requestCode, Activity.RESULT_OK, Intent().setData(uri))
            }
            val token = saved.await() as String
            assertNull(saved.errorCode)
            scenario.onActivity { handler.dispose() }
            assertArrayEquals(bytes, file.readBytes())
            assertTrue(PendingBackupExportStore(root).get(token)!!.verified)
            store.complete(token)
            file.parentFile?.deleteRecursively()
            root.deleteRecursively()
        }
    }

    @Test fun replacementHandlerProcessesSaveResultWithoutTheOriginalDartResult() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val launched = CountDownLatch(1)
            val original = Result()
            lateinit var handler: RecordBackupHandler
            lateinit var store: PendingBackupExportStore
            lateinit var root: File
            lateinit var file: File
            lateinit var uri: Uri
            val bytes = byteArrayOf(7, 8, 9)
            scenario.onActivity { activity ->
                root = File(activity.filesDir, "export-test-${System.nanoTime()}")
                store = PendingBackupExportStore(root)
                file = BackupShareCache.write(File(activity.cacheDir, "record-backup-share"), "recreated.yhb", byteArrayOf(0))
                uri = FileProvider.getUriForFile(activity, "${activity.packageName}.diagnostics", file)
                handler = RecordBackupHandler(activity, { _, _ -> launched.countDown() }, exportStore = store)
                handler.onMethodCall(MethodCall("saveFile", mapOf("name" to "recreated.yhb", "bytes" to bytes)), original)
            }
            assertTrue(launched.await(10, TimeUnit.SECONDS))
            val entry = store.awaitingPicker()!!
            val token = entry.token
            val completed = Result()
            scenario.onActivity { handler.dispose() }
            scenario.recreate()
            scenario.onActivity { activity ->
                handler = RecordBackupHandler(activity, { _, _ -> }, exportStore = PendingBackupExportStore(root))
                handler.onActivityResult(entry.requestCode, Activity.RESULT_OK, Intent().setData(uri))
                handler.onActivityResult(entry.requestCode, Activity.RESULT_OK, Intent().setData(uri))
                handler.onMethodCall(MethodCall("completeSavedFile", mapOf("token" to token)), completed)
            }
            completed.await()
            assertNull(completed.errorCode)
            assertArrayEquals(bytes, file.readBytes())
            scenario.onActivity { handler.dispose() }
            file.parentFile?.deleteRecursively()
            root.deleteRecursively()
        }
    }

    @Test fun disposingDuringWriteCompletesTheDartReplyAndKeepsWriting() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val launched = CountDownLatch(1)
            val enteredWrite = CountDownLatch(1)
            val releaseWrite = CountDownLatch(1)
            val saved = Result()
            lateinit var handler: RecordBackupHandler
            lateinit var root: File
            lateinit var store: PendingBackupExportStore
            var written: ByteArray? = null
            val bytes = byteArrayOf(4, 5, 6)
            val documents = object : PendingBackupExportStore.Documents {
                override fun write(uri: String, source: File) {
                    enteredWrite.countDown()
                    check(releaseWrite.await(10, TimeUnit.SECONDS))
                    written = source.readBytes()
                }
                override fun matches(uri: String, source: File) = written?.contentEquals(bytes) == true
                override fun delete(uri: String): Boolean = error("Disposal must not delete the export")
            }
            try {
                scenario.onActivity { activity ->
                    root = File(activity.filesDir, "export-test-${System.nanoTime()}")
                    store = PendingBackupExportStore(root)
                    handler = RecordBackupHandler(activity, { _, _ -> launched.countDown() },
                        exportStore = store, exportDocumentsOverride = documents)
                    handler.onMethodCall(MethodCall("saveFile", mapOf("name" to "slow.yhb", "bytes" to bytes)), saved)
                }
                assertTrue(launched.await(10, TimeUnit.SECONDS))
                val entry = store.awaitingPicker()!!
                val token = entry.token
                scenario.onActivity {
                    handler.onActivityResult(entry.requestCode, Activity.RESULT_OK,
                        Intent().setData(Uri.parse("content://backup-test/slow")))
                }
                assertTrue(enteredWrite.await(10, TimeUnit.SECONDS))
                scenario.onActivity { handler.dispose() }
                saved.await()
                assertEquals("picker_cancelled", saved.errorCode)
                releaseWrite.countDown()
                // Serialize through the store's transaction lock after the
                // writer; a discarded Activity must still reach verified.
                store.writeAndVerify(token, documents)
                assertTrue(store.get(token)!!.verified)
                assertArrayEquals(bytes, written)
                store.complete(token)
            } finally {
                releaseWrite.countDown()
                runCatching { root.deleteRecursively() }
            }
        }
    }

    @Test fun failedDocumentDeletionDoesNotBlockTheNextPicker() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val launched = CountDownLatch(1)
            val failed = Result()
            lateinit var handler: RecordBackupHandler
            lateinit var root: File
            lateinit var store: PendingBackupExportStore
            scenario.onActivity { activity ->
                root = File(activity.filesDir, "export-test-${System.nanoTime()}")
                store = PendingBackupExportStore(root)
                handler = RecordBackupHandler(activity, { _, _ -> launched.countDown() },
                    deleteSavedDocument = { false }, exportStore = store)
                handler.onMethodCall(MethodCall("saveFile", mapOf("name" to "first.yhb", "bytes" to byteArrayOf(1))), failed)
            }
            assertTrue(launched.await(10, TimeUnit.SECONDS))
            val requestCode = store.awaitingPicker()!!.requestCode
            scenario.onActivity {
                handler.onActivityResult(requestCode, Activity.RESULT_OK,
                    Intent().setData(Uri.parse("content://example.test/denied")))
            }
            failed.await()
            assertEquals("backup_save_failed", failed.errorCode)
            val nextLaunch = CountDownLatch(1)
            val next = Result()
            scenario.onActivity { activity ->
                handler.dispose()
                handler = RecordBackupHandler(activity, { _, _ -> nextLaunch.countDown() }, exportStore = store)
                handler.onMethodCall(MethodCall("saveFile", mapOf("name" to "second.yhb", "bytes" to byteArrayOf(2))), next)
            }
            assertTrue(nextLaunch.await(10, TimeUnit.SECONDS))
            val nextCode = store.awaitingPicker()!!.requestCode
            scenario.onActivity { handler.onActivityResult(nextCode, Activity.RESULT_CANCELED, null) }
            assertNull(next.await())
            assertNull(next.errorCode)
            scenario.onActivity { handler.dispose() }
            root.deleteRecursively()
        }
    }

    @Test fun oldPickerResultsCannotOverwriteACompletedExportOrCancelTheNextOne() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var handler: RecordBackupHandler
            lateinit var store: PendingBackupExportStore
            lateinit var root: File
            lateinit var firstFile: File
            lateinit var secondFile: File
            lateinit var firstUri: Uri
            lateinit var secondUri: Uri
            var launched = CountDownLatch(1)
            val firstSaved = Result()
            val firstBytes = byteArrayOf(1, 2, 3)
            val secondBytes = byteArrayOf(4, 5, 6)
            scenario.onActivity { activity ->
                root = File(activity.filesDir, "export-test-${System.nanoTime()}")
                store = PendingBackupExportStore(root)
                firstFile = BackupShareCache.write(File(activity.cacheDir, "record-backup-share"), "first.yhb", byteArrayOf(0))
                secondFile = BackupShareCache.write(File(activity.cacheDir, "record-backup-share"), "second.yhb", byteArrayOf(0))
                firstUri = FileProvider.getUriForFile(activity, "${activity.packageName}.diagnostics", firstFile)
                secondUri = FileProvider.getUriForFile(activity, "${activity.packageName}.diagnostics", secondFile)
                handler = RecordBackupHandler(activity, { _, _ -> launched.countDown() }, exportStore = store)
                handler.onMethodCall(MethodCall("saveFile", mapOf("name" to "first.yhb", "bytes" to firstBytes)), firstSaved)
            }
            assertTrue(launched.await(10, TimeUnit.SECONDS))
            val firstEntry = store.awaitingPicker()!!
            scenario.onActivity { handler.onActivityResult(firstEntry.requestCode, Activity.RESULT_OK, Intent().setData(firstUri)) }
            val firstToken = firstSaved.await() as String
            val completed = Result()
            scenario.onActivity { handler.onMethodCall(MethodCall("completeSavedFile", mapOf("token" to firstToken)), completed) }
            completed.await()
            assertNull(completed.errorCode)
            launched = CountDownLatch(1)
            val secondSaved = Result()
            scenario.onActivity { handler.onMethodCall(MethodCall("saveFile", mapOf("name" to "second.yhb", "bytes" to secondBytes)), secondSaved) }
            assertTrue(launched.await(10, TimeUnit.SECONDS))
            val secondEntry = store.awaitingPicker()!!
            assertNotEquals(firstEntry.requestCode, secondEntry.requestCode)
            scenario.onActivity {
                handler.onActivityResult(firstEntry.requestCode, Activity.RESULT_OK, Intent().setData(firstUri))
                handler.onActivityResult(firstEntry.requestCode, Activity.RESULT_CANCELED, null)
            }
            assertArrayEquals(firstBytes, firstFile.readBytes())
            assertNull(store.get(secondEntry.token)!!.uri)
            scenario.onActivity { handler.onActivityResult(secondEntry.requestCode, Activity.RESULT_OK, Intent().setData(secondUri)) }
            val secondToken = secondSaved.await() as String
            assertNull(secondSaved.errorCode)
            assertArrayEquals(firstBytes, firstFile.readBytes())
            assertArrayEquals(secondBytes, secondFile.readBytes())
            store.complete(secondToken)
            scenario.onActivity { handler.dispose() }
            firstFile.parentFile?.deleteRecursively()
            secondFile.parentFile?.deleteRecursively()
            root.deleteRecursively()
        }
    }

    @Test fun preparedShareCanBeDiscardedBeforeOpeningTheSharesheet() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val name = "discard-${System.nanoTime()}.yhb"
            lateinit var handler: RecordBackupHandler
            lateinit var root: File
            val prepared = Result()
            scenario.onActivity { activity ->
                root = File(activity.cacheDir, "record-backup-share")
                handler = RecordBackupHandler(activity, { _, _ -> })
                handler.onMethodCall(MethodCall("prepareShareFile", mapOf("name" to name, "bytes" to byteArrayOf(7, 8))), prepared)
            }
            val token = prepared.await() as String
            assertNull(prepared.errorCode)
            val preparedFile = root.walkTopDown().first { it.isFile && it.name == name }
            val discarded = Result()
            scenario.onActivity { handler.onMethodCall(MethodCall("discardShareFile", mapOf("token" to token)), discarded) }
            discarded.await()
            assertNull(discarded.errorCode)
            assertFalse(preparedFile.exists())
            scenario.onActivity { handler.dispose() }
        }
    }

    @Test fun providerTimeoutUnblocksDartAndTheNextPickerWhileTheLateWriteStaysSafe() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            var launched = CountDownLatch(1)
            val entered = CountDownLatch(1)
            val release = CountDownLatch(1)
            val original = Result()
            lateinit var handler: RecordBackupHandler
            lateinit var store: PendingBackupExportStore
            lateinit var root: File
            val expected = byteArrayOf(7, 8, 9)
            var written: ByteArray? = null
            val deletions = AtomicInteger()
            val documents = object : PendingBackupExportStore.Documents {
                override fun write(uri: String, source: File) {
                    entered.countDown()
                    check(release.await(10, TimeUnit.SECONDS))
                    written = source.readBytes()
                }
                override fun matches(uri: String, source: File) = written?.contentEquals(source.readBytes()) == true
                override fun delete(uri: String): Boolean { deletions.incrementAndGet(); return true }
            }
            try {
                scenario.onActivity { activity ->
                    root = File(activity.filesDir, "export-timeout-test-${System.nanoTime()}")
                    store = PendingBackupExportStore(root)
                    handler = RecordBackupHandler(activity, { _, _ -> launched.countDown() },
                        exportStore = store, exportDocumentsOverride = documents, exportTimeoutMillis = 1_000)
                    handler.onMethodCall(MethodCall("saveFile", mapOf("name" to "slow.yhb", "bytes" to expected)), original)
                }
                assertTrue(launched.await(10, TimeUnit.SECONDS))
                val first = store.awaitingPicker()!!
                scenario.onActivity {
                    handler.onActivityResult(first.requestCode, Activity.RESULT_OK,
                        Intent().setData(Uri.parse("content://backup-test/slow")))
                }
                assertTrue(entered.await(10, TimeUnit.SECONDS))
                original.await()
                assertEquals("backup_save_failed", original.errorCode)
                assertArrayEquals(expected, store.sourceFile(first.token).readBytes())
                launched = CountDownLatch(1)
                val next = Result()
                scenario.onActivity {
                    handler.onMethodCall(MethodCall("saveFile", mapOf("name" to "next.yhb", "bytes" to byteArrayOf(1))), next)
                }
                assertTrue("The next picker must not queue behind the stuck provider", launched.await(5, TimeUnit.SECONDS))
                val second = store.awaitingPicker()!!
                scenario.onActivity { handler.onActivityResult(second.requestCode, Activity.RESULT_CANCELED, null) }
                next.await()
                assertNull(next.errorCode)
                release.countDown()
                store.writeAndVerify(first.token, documents)
                assertTrue(store.get(first.token)!!.verified)
                assertArrayEquals(expected, written)
                assertEquals(1, original.replies.get())
                assertEquals(0, deletions.get())
            } finally {
                release.countDown()
                scenario.onActivity { handler.dispose() }
                root.deleteRecursively()
            }
        }
    }

    @Test fun pickerWaitIsNotSubjectToTheDocumentIoDeadline() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val launched = CountDownLatch(1)
            val result = Result()
            lateinit var handler: RecordBackupHandler
            lateinit var root: File
            lateinit var store: PendingBackupExportStore
            scenario.onActivity { activity ->
                root = File(activity.filesDir, "export-picker-wait-test-${System.nanoTime()}")
                store = PendingBackupExportStore(root)
                handler = RecordBackupHandler(activity, { _, _ -> launched.countDown() },
                    exportStore = store, exportTimeoutMillis = 1_000)
                handler.onMethodCall(MethodCall("saveFile", mapOf("name" to "wait.yhb", "bytes" to byteArrayOf(1))), result)
            }
            try {
                assertTrue(launched.await(10, TimeUnit.SECONDS))
                assertFalse("Choosing a destination is not provider I/O", result.repliedWithin(1_500))
                val entry = store.awaitingPicker()!!
                scenario.onActivity { handler.onActivityResult(entry.requestCode, Activity.RESULT_CANCELED, null) }
                result.await()
                assertNull(result.errorCode)
                assertEquals(1, result.replies.get())
            } finally {
                scenario.onActivity { handler.dispose() }
                root.deleteRecursively()
            }
        }
    }
}
