package app.yahagi.kancollebrowser.backup

import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class PendingBackupExportStoreTest {
    private class Documents : PendingBackupExportStore.Documents {
        val bytes = mutableMapOf<String, ByteArray>()
        var writes = 0
        var deletions = 0
        var failWrite = false
        var allowDelete = true
        override fun write(uri: String, source: File) {
            writes++
            bytes[uri] = source.readBytes().let { if (failWrite) it.copyOf(1) else it }
            if (failWrite) throw IOException("Provider failed during write")
        }
        override fun matches(uri: String, source: File) =
            bytes[uri]?.contentEquals(source.readBytes()) == true
        override fun delete(uri: String): Boolean {
            deletions++
            if (!allowDelete) return false
            bytes.remove(uri)
            return true
        }
    }

    private fun withRoot(test: (File) -> Unit) {
        val root = Files.createTempDirectory("pending-backup-export-").toFile()
        try { test(root) } finally { root.deleteRecursively() }
    }

    @Test fun completeBytesAreDurableBeforeThePickerCanCreateADocument() = withRoot { root ->
        val expected = byteArrayOf(1, 2, 3, 4)
        val entry = PendingBackupExportStore(root).stage("backup.yhb", expected)
        val reopened = PendingBackupExportStore(root)
        val pending = reopened.awaitingPicker()!!
        assertEquals(entry.token, pending.token)
        assertNull(pending.uri)
        assertArrayEquals(expected, reopened.sourceFile(entry.token).readBytes())
    }

    @Test fun newStoreFinishesASelectedDocumentAfterProcessDeathMidWrite() = withRoot { root ->
        val documents = Documents()
        val store = PendingBackupExportStore(root)
        val entry = store.stage("backup.yhb", byteArrayOf(1, 2, 3, 4))
        store.select(entry.token, "content://backup/1", 3)
        documents.bytes["content://backup/1"] = byteArrayOf(1)
        val reopened = PendingBackupExportStore(root)
        reopened.recover(documents)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), documents.bytes["content://backup/1"])
        assertTrue(reopened.get(entry.token)!!.verified)
        assertEquals(3, reopened.get(entry.token)!!.grantFlags)
    }

    @Test fun verifiedDocumentSurvivesRestartWithoutDartCompletion() = withRoot { root ->
        val documents = Documents()
        val store = PendingBackupExportStore(root)
        val entry = store.stage("backup.yhb", byteArrayOf(5, 6, 7))
        store.select(entry.token, "content://backup/1", 3)
        store.writeAndVerify(entry.token, documents)
        val writes = documents.writes
        val reopened = PendingBackupExportStore(root)
        reopened.recover(documents)
        assertEquals(writes, documents.writes)
        assertEquals(0, documents.deletions)
        assertArrayEquals(byteArrayOf(5, 6, 7), documents.bytes["content://backup/1"])
        reopened.complete(entry.token)
        reopened.complete(entry.token)
        assertNull(reopened.get(entry.token))
        assertTrue(documents.bytes.containsKey("content://backup/1"))
    }

    @Test fun explicitDiscardDeletesEvenAVerifiedExport() = withRoot { root ->
        val documents = Documents()
        val store = PendingBackupExportStore(root)
        val entry = store.stage("backup.yhb", byteArrayOf(5, 6, 7))
        store.select(entry.token, "content://backup/1", 3)
        store.writeAndVerify(entry.token, documents)
        assertTrue(store.discard(entry.token, documents))
        assertTrue(store.discard(entry.token, documents))
        assertFalse(documents.bytes.containsKey("content://backup/1"))
        assertNull(store.get(entry.token))
    }

    @Test fun cancelledPickerOnlyRemovesTheUnselectedStage() = withRoot { root ->
        val store = PendingBackupExportStore(root)
        val entry = store.stage("backup.yhb", byteArrayOf(1, 2))
        store.cancelPicker(entry.token)
        assertNull(store.awaitingPicker())
        assertFalse(store.sourceFile(entry.token).exists())
    }

    @Test fun completionCannotAcknowledgeAnUnverifiedTarget() = withRoot { root ->
        val store = PendingBackupExportStore(root)
        val entry = store.stage("backup.yhb", byteArrayOf(1, 2))
        store.select(entry.token, "content://backup/1", 3)
        assertThrows(IllegalArgumentException::class.java) { store.complete(entry.token) }
        assertNotNull(store.get(entry.token))
    }

    @Test fun pickerRequestIdentitySurvivesCompletionAndStoreReplacement() = withRoot { root ->
        val documents = Documents()
        val store = PendingBackupExportStore(root)
        val first = store.stage("first.yhb", byteArrayOf(1, 2))
        store.select(first.token, "content://backup/1", 3)
        store.writeAndVerify(first.token, documents)
        store.complete(first.token)
        val reopened = PendingBackupExportStore(root)
        val second = reopened.stage("second.yhb", byteArrayOf(3, 4))
        assertNotEquals(first.requestCode, second.requestCode)
        assertNull(reopened.forPicker(first.requestCode))
        assertEquals(second.token, reopened.forPicker(second.requestCode)!!.token)
    }

    @Test fun failedPrivateCleanupStillAcknowledgesVerifiedExport() = withRoot { root ->
        val documents = Documents()
        val store = PendingBackupExportStore(root, removeCompletedTransaction = { false })
        val entry = store.stage("backup.yhb", byteArrayOf(1, 2))
        store.select(entry.token, "content://backup/1", 3)
        store.writeAndVerify(entry.token, documents)
        store.complete(entry.token)
        assertTrue(store.get(entry.token)!!.verified)
        assertTrue(documents.bytes.containsKey("content://backup/1"))
        assertEquals(0, documents.deletions)
    }

    @Test fun recoveryReclaimsPayloadWhoseStageWasInterruptedBeforeMetadata() = withRoot { root ->
        val orphan = File(root, "00000000-0000-0000-0000-000000000001").apply { mkdir() }
        File(orphan, "payload.yhb").writeBytes(byteArrayOf(1, 2, 3))
        PendingBackupExportStore(root).recover(Documents())
        assertFalse(orphan.exists())
    }

    @Test fun failedCleanupRemainsRetryableWithoutBlockingAnotherExport() = withRoot { root ->
        val documents = Documents().apply { failWrite = true; allowDelete = false }
        val store = PendingBackupExportStore(root)
        val entry = store.stage("first.yhb", byteArrayOf(1, 2, 3))
        store.select(entry.token, "content://backup/1", 3)
        store.recover(documents)
        assertTrue(store.get(entry.token)!!.discardRequested)
        val next = store.stage("next.yhb", byteArrayOf(4, 5))
        assertEquals(next.token, store.awaitingPicker()!!.token)
        documents.allowDelete = true
        PendingBackupExportStore(root).recover(documents)
        assertNull(store.get(entry.token))
        assertNotNull(store.get(next.token))
    }

    @Test fun duplicatePickerDeliveryAndConcurrentWritersDoNotRewriteVerifiedTarget() = withRoot { root ->
        val documents = Documents()
        val store = PendingBackupExportStore(root)
        val entry = store.stage("backup.yhb", byteArrayOf(1, 2, 3))
        store.select(entry.token, "content://backup/1", 3)
        store.select(entry.token, "content://backup/1", 3)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val first = executor.submit { store.writeAndVerify(entry.token, documents) }
            val second = executor.submit {
                PendingBackupExportStore(root).writeAndVerify(entry.token, documents)
            }
            first.get(5, TimeUnit.SECONDS)
            second.get(5, TimeUnit.SECONDS)
            assertEquals(1, documents.writes)
        } finally { executor.shutdownNow() }
    }

    @Test fun slowRecoveryDoesNotHoldTheStoreLockForNewStaging() = withRoot { root ->
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        var written = false
        val documents = object : PendingBackupExportStore.Documents {
            override fun write(uri: String, source: File) {
                entered.countDown()
                check(release.await(5, TimeUnit.SECONDS))
                written = true
            }
            override fun matches(uri: String, source: File) = written
            override fun delete(uri: String) = true
        }
        val store = PendingBackupExportStore(root)
        val entry = store.stage("first.yhb", byteArrayOf(1))
        store.select(entry.token, "content://backup/1", 3)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val writing = executor.submit { store.writeAndVerify(entry.token, documents) }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            val next = executor.submit<PendingBackupExportStore.Entry> {
                PendingBackupExportStore(root).stage("next.yhb", byteArrayOf(2))
            }.get(2, TimeUnit.SECONDS)
            assertNotEquals(entry.token, next.token)
            release.countDown()
            writing.get(5, TimeUnit.SECONDS)
        } finally { release.countDown(); executor.shutdownNow() }
    }

    @Test fun recoveryKeepsACompleteDocumentWhenReadbackTemporarilyFails() = withRoot { root ->
        val expected = byteArrayOf(1, 2, 3)
        var written: ByteArray? = null
        var deletions = 0
        val documents = object : PendingBackupExportStore.Documents {
            override fun write(uri: String, source: File) { written = source.readBytes() }
            override fun matches(uri: String, source: File): Boolean {
                if (written == null) return false
                throw IOException("Cloud provider is temporarily offline after write")
            }
            override fun delete(uri: String): Boolean { deletions++; written = null; return true }
        }
        val store = PendingBackupExportStore(root)
        val entry = store.stage("backup.yhb", expected)
        store.select(entry.token, "content://backup/1", 3)
        store.recover(documents)
        assertEquals("An unreadable target is not proven incomplete", 0, deletions)
        assertArrayEquals(expected, written)
        assertNotNull(store.get(entry.token))
        assertArrayEquals(expected, store.sourceFile(entry.token).readBytes())
    }

    @Test fun recoveryAcknowledgesACompleteWriteWhoseFirstReadbackFailed() = withRoot { root ->
        val expected = byteArrayOf(4, 5, 6)
        var written: ByteArray? = null
        var reads = 0
        var deletions = 0
        val documents = object : PendingBackupExportStore.Documents {
            override fun write(uri: String, source: File) { written = source.readBytes() }
            override fun matches(uri: String, source: File): Boolean {
                if (written == null) return false
                if (++reads == 1) throw IOException("Transient read failure")
                return written?.contentEquals(source.readBytes()) == true
            }
            override fun delete(uri: String): Boolean { deletions++; written = null; return true }
        }
        val store = PendingBackupExportStore(root)
        val entry = store.stage("backup.yhb", expected)
        store.select(entry.token, "content://backup/1", 3)
        store.recover(documents)
        assertEquals(0, deletions)
        assertArrayEquals(expected, written)
        assertTrue(store.get(entry.token)!!.verified)
    }

    @Test fun recoveryDoesNotTruncateACompleteTargetBeforeItsVerifiedMarkerWasPersisted() = withRoot { root ->
        val expected = byteArrayOf(7, 8, 9)
        val documents = Documents().apply {
            bytes["content://backup/1"] = expected
            failWrite = true // Reopening this complete target for rwt would destroy it.
        }
        val store = PendingBackupExportStore(root)
        val entry = store.stage("backup.yhb", expected)
        store.select(entry.token, "content://backup/1", 3)
        PendingBackupExportStore(root).recover(documents)
        assertEquals("A complete recovered document needs no second write", 0, documents.writes)
        assertArrayEquals(expected, documents.bytes["content://backup/1"])
        assertEquals(0, documents.deletions)
        assertTrue(store.get(entry.token)!!.verified)
    }
}
