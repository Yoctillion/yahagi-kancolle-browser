package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.FilterInputStream
import java.util.Random
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class GameModArchiveProgressTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun `large archive exposes real streamed bytes before preflight returns`() {
        val bytes = ByteArray(96 * 1024).also { Random(17).nextBytes(it) }
        val zipped = ByteArrayOutputStream().also { output ->
            ZipOutputStream(output).use { zip ->
                zip.putNextEntry(ZipEntry("readme.bin")); zip.write(bytes); zip.closeEntry()
                zip.putNextEntry(ZipEntry("extra/note.txt")); zip.write("note".toByteArray()); zip.closeEntry()
            }
        }.toByteArray()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val failure = AtomicReference<Throwable?>()
        val input = object : FilterInputStream(zipped.inputStream()) {
            var reads = 0
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                if (++reads == 3) {
                    entered.countDown()
                    check(release.await(10, TimeUnit.SECONDS))
                }
                return super.read(buffer, offset, length)
            }
        }
        val progress = GameModProgress()
        val id = progress.begin("import")
        progress.startPackage("read", "large.zip", 0, 1)
        val destination = temporary.newFolder()
        val worker = Thread {
            try { progress.withOperation(id) { GameModArchive(progress).unpack(input, "large.zip", destination) } }
            catch (error: Throwable) { failure.set(error) }
        }
        worker.start()
        try {
            assertTrue("Archive copy must reach the controlled stream", entered.await(10, TimeUnit.SECONDS))
            val live = progress.snapshot()!!
            assertEquals("read", live["phase"])
            assertTrue((live["completedBytes"] as Long) > 0L)
            assertTrue((live["completedBytes"] as Long) < zipped.size)
            assertNull("Streaming source size is unknown", live["totalBytes"])
        } finally { release.countDown(); worker.join(10_000) }
        assertFalse("Archive worker must finish", worker.isAlive)
        failure.get()?.let { throw AssertionError("Archive validation failed", it) }
        val checked = progress.snapshot()!!
        assertEquals("validate", checked["phase"])
        assertEquals(2, checked["completedFiles"])
        assertEquals(2, checked["totalFiles"])
        assertEquals(bytes.size.toLong() + 4L, checked["completedBytes"])
        assertEquals(bytes.size.toLong() + 4L, checked["totalBytes"])
    }
}
