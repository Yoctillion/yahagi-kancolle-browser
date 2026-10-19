package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class GameModProgressTest {
    @Test fun `discovery has unknown totals and completion retains identity`() {
        var now = 20L
        val progress = GameModProgress { now }
        assertNull(progress.snapshot())
        val id = progress.begin("scan")
        val initial = progress.snapshot()!!
        assertEquals(id, initial["operationId"])
        assertEquals("discover", initial["phase"])
        assertNull(initial["totalPackages"])
        assertEquals(true, initial["active"])
        now = 345L
        progress.finish(id)
        val done = progress.snapshot()!!
        assertEquals(id, done["operationId"])
        assertEquals(false, done["active"])
        assertEquals(325L, done["elapsedMillis"])
        now = 800L
        assertEquals(325L, progress.snapshot()!!["elapsedMillis"])
    }

    @Test fun `large package advances inner progress and next package clears it`() {
        val progress = GameModProgress()
        progress.begin("scan")
        progress.startPackage("read", "Large", 27, 60)
        progress.files(12, 300, "kcs2/resources/a.png", 4096L, 80000L)
        assertEquals(27, progress.snapshot()!!["completedPackages"])
        assertEquals(12, progress.snapshot()!!["completedFiles"])
        progress.files(24, 300, "kcs2/resources/b.png", 8192L, 80000L)
        assertEquals(8192L, progress.snapshot()!!["completedBytes"])
        progress.startPackage("validate", "Next", 28, 60)
        val next = progress.snapshot()!!
        assertEquals(28, next["completedPackages"])
        assertEquals(0, next["completedFiles"])
        assertNull(next["totalFiles"])
        assertNull(next["currentFile"])
        assertEquals(0L, next["completedBytes"])
    }

    @Test fun `late finish cannot finish a newer operation`() {
        val progress = GameModProgress()
        val first = progress.begin("scan")
        val second = progress.begin("import")
        assertNotEquals(first, second)
        progress.finish(first)
        assertEquals(second, progress.snapshot()!!["operationId"])
        assertEquals(true, progress.snapshot()!!["active"])
        progress.finish(second)
        assertEquals(false, progress.snapshot()!!["active"])
    }

    @Test fun `progress remains readable while file worker is blocked`() {
        val progress = GameModProgress()
        val id = progress.begin("scan")
        val workerEntered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val worker = Thread {
            progress.withOperation(id) {
                progress.startPackage("read", "Large", 27, 60)
                workerEntered.countDown()
                release.await(3, TimeUnit.SECONDS)
            }
        }
        worker.start()
        try {
            assertTrue(workerEntered.await(1, TimeUnit.SECONDS))
            assertEquals(27, progress.snapshot()!!["completedPackages"])
            assertEquals(true, progress.snapshot()!!["active"])
        } finally { release.countDown(); worker.join() }
    }

    @Test fun `old activity producer cannot overwrite a new operation snapshot`() {
        val progress = GameModProgress()
        val oldStarted = CountDownLatch(1)
        val release = CountDownLatch(1)
        val oldWorker = Thread {
            val old = progress.begin("scan")
            progress.startPackage("read", "Old", 27, 60)
            oldStarted.countDown()
            release.await(10, TimeUnit.SECONDS)
            progress.startPackage("read", "Stale", 28, 60)
            progress.files(200, 300, "old.png", 9000L, 10000L)
            progress.update(phase = "save", completedPackages = 29)
            progress.finish(old)
        }
        oldWorker.start()
        try {
            assertTrue(oldStarted.await(10, TimeUnit.SECONDS))
            val current = progress.begin("import")
            progress.startPackage("import", "Current", 0, 1)
            release.countDown()
            oldWorker.join(10_000)
            assertFalse(oldWorker.isAlive)
            val snapshot = progress.snapshot()!!
            assertEquals(current, snapshot["operationId"])
            assertEquals(true, snapshot["active"])
            assertEquals("Current", snapshot["currentPackage"])
            assertEquals("import", snapshot["phase"])
            assertEquals(0, snapshot["completedPackages"])
            assertEquals(0L, snapshot["completedBytes"])
            assertNull(snapshot["currentFile"])
        } finally { release.countDown(); oldWorker.join(10_000) }
    }
}
