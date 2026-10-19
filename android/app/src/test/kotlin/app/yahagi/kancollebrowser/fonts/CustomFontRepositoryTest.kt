package app.yahagi.kancollebrowser.fonts

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.io.SequenceInputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class CustomFontRepositoryTest {
    @get:Rule val temporaryFolder = TemporaryFolder()

    @Test fun `copies a single TrueType font privately using its content hash`() {
        val root = temporaryFolder.newFolder("custom_fonts")
        val bytes = font()
        var decoded = false
        val repository = CustomFontRepository(root) { file ->
            assertArrayEquals(bytes, file.readBytes())
            decoded = true
        }

        val imported = repository.importFont(bytes.inputStream(), "我的字体.ttf")

        assertTrue(decoded)
        assertEquals(sha256(bytes), imported.id)
        assertEquals("我的字体.ttf", imported.name)
        assertEquals(File(root.canonicalFile, "${imported.id}.ttf").absolutePath, imported.path)
        assertArrayEquals(bytes, File(imported.path).readBytes())
        assertEquals(setOf("${imported.id}.ttf"), root.list()!!.toSet())
    }

    @Test fun `recognizes supported formats from contents rather than the document suffix`() {
        for ((signature, extension) in listOf(0x00010000 to "ttf", 0x74727565 to "ttf", 0x4f54544f to "otf")) {
            val root = temporaryFolder.newFolder()
            val imported = CustomFontRepository(root).importFont(font(signature).inputStream(), "download.bin")
            assertTrue(imported.path.endsWith(".$extension"))
            assertEquals("download.bin", imported.name)
        }
    }

    @Test fun `importing identical bytes reuses one stable file`() {
        val root = temporaryFolder.newFolder()
        val repository = CustomFontRepository(root)
        val first = repository.importFont(font().inputStream(), "first.ttf")
        val second = repository.importFont(font().inputStream(), "second.ttf")
        assertEquals(first.id, second.id)
        assertEquals(first.path, second.path)
        assertEquals("second.ttf", second.name)
        assertEquals(1, root.list()!!.size)
    }

    @Test fun `rejects unsupported collections web fonts and non-font files without leftovers`() {
        for (bytes in listOf(byteArrayOf(), "not a font".toByteArray(), font(0x74746366), font(0x774f4646))) {
            val root = temporaryFolder.newFolder()
            assertEquals("invalid_font", failure { CustomFontRepository(root).importFont(bytes.inputStream(), "test.ttf") }.code)
            assertTrue(root.list()!!.isEmpty())
        }
    }

    @Test fun `rejects truncated or impossible sfnt table directories and ranges`() {
        val invalid = listOf(
            font().copyOf(20),
            font().also { buffer(it).putShort(4, 0) },
            font().also { buffer(it).putShort(4, 100) },
            font().also { buffer(it).putInt(20, 0) },
            font().also { buffer(it).putInt(20, 45) },
            font().also { buffer(it).putInt(24, Int.MAX_VALUE) },
            font().also { buffer(it).putInt(20, -4) },
            font().also { buffer(it).putInt(36, 44) },
            font().also { buffer(it).putInt(28, 0x68656164) },
        )
        for (bytes in invalid) {
            val root = temporaryFolder.newFolder()
            assertEquals("invalid_font", failure { CustomFontRepository(root).importFont(bytes.inputStream(), "broken.otf") }.code)
            assertTrue(root.list()!!.isEmpty())
        }
    }

    @Test fun `enforces the 32 MiB limit while streaming an unknown length source`() {
        val root = temporaryFolder.newFolder()
        var remaining = 32L * 1024 * 1024 + 1
        var closed = false
        val stream = object : InputStream() {
            override fun read(): Int = if (remaining-- > 0) 0 else -1
            override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
                if (remaining <= 0) return -1
                val count = minOf(remaining, length.toLong()).toInt()
                bytes.fill(0, offset, offset + count)
                remaining -= count
                return count
            }
            override fun close() { closed = true }
        }
        assertEquals("font_too_large", failure { CustomFontRepository(root).importFont(stream, "huge.ttf") }.code)
        assertTrue(closed)
        assertTrue(root.list()!!.isEmpty())
    }

    @Test fun `a read failure cleans its temporary file and closes the source`() {
        val root = temporaryFolder.newFolder()
        var closed = false
        val stream = object : InputStream() {
            override fun read(): Int = throw IOException("provider disconnected")
            override fun close() { closed = true }
        }
        failure { CustomFontRepository(root).importFont(stream, "lost.ttf") }
        assertTrue(closed)
        assertTrue(root.list()!!.isEmpty())
    }

    @Test fun `a source close failure cannot publish a font`() {
        val root = temporaryFolder.newFolder()
        val source = object : ByteArrayInputStream(font()) {
            override fun close() { throw IOException("provider close failed") }
        }
        failure { CustomFontRepository(root).importFont(source, "test.ttf") }
        assertTrue(root.list()!!.isEmpty())
    }

    @Test fun `accepts short reads and the exact 32 MiB boundary`() {
        val root = temporaryFolder.newFolder()
        val prefix = font()
        val source = SequenceInputStream(prefix.inputStream(), object : InputStream() {
            var remaining = CustomFontRepository.MAX_BYTES - prefix.size
            override fun read(): Int = if (remaining-- > 0) 0 else -1
            override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
                if (remaining <= 0) return -1
                val count = minOf(remaining, length.toLong(), 997).toInt()
                bytes.fill(0, offset, offset + count)
                remaining -= count
                return count
            }
        })
        val imported = CustomFontRepository(root).importFont(source, "large.ttf")
        assertEquals(CustomFontRepository.MAX_BYTES, File(imported.path).length())
        assertEquals(1, root.list()!!.size)
    }

    @Test fun `cancellation after decoding does not publish the font`() {
        val root = temporaryFolder.newFolder()
        var cancelled = false
        val repository = CustomFontRepository(root) { cancelled = true }
        assertEquals("activity_destroyed", failure {
            repository.importFont(font().inputStream(), "cancelled.ttf") { cancelled }
        }.code)
        assertTrue(root.list()!!.isEmpty())
    }

    @Test fun `a failed import preserves an existing valid font`() {
        val root = temporaryFolder.newFolder()
        val repository = CustomFontRepository(root)
        val imported = repository.importFont(font().inputStream(), "good.ttf")
        failure { repository.importFont(byteArrayOf(1, 2, 3).inputStream(), "bad.ttf") }
        assertArrayEquals(font(), File(imported.path).readBytes())
        assertEquals(1, root.list()!!.size)
    }

    @Test fun `platform font decoder failure never installs the selected file`() {
        val root = temporaryFolder.newFolder()
        val repository = CustomFontRepository(root) { throw IllegalArgumentException("cannot decode font") }
        assertEquals("invalid_font", failure { repository.importFont(font().inputStream(), "bad.ttf") }.code)
        assertTrue(root.list()!!.isEmpty())
    }

    @Test fun `removal only accepts a hash and leaves unrelated files untouched`() {
        val root = temporaryFolder.newFolder()
        val repository = CustomFontRepository(root)
        val imported = repository.importFont(font().inputStream(), "test.ttf")
        val unrelated = File(root, "keep.txt").also { it.writeText("keep") }
        val outside = temporaryFolder.newFile("outside.ttf")
        for (id in listOf("../outside", outside.absolutePath, "", "A".repeat(64), "0".repeat(63))) {
            assertEquals("invalid_font_id", failure { repository.removeFont(id) }.code)
        }
        repository.removeFont(imported.id)
        repository.removeFont(imported.id)
        assertFalse(File(imported.path).exists())
        assertTrue(unrelated.exists())
        assertTrue(outside.exists())
    }

    @Test fun `startup cleanup removes abandoned imports while retaining the saved font`() {
        val root = temporaryFolder.newFolder()
        val repository = CustomFontRepository(root)
        val saved = repository.importFont(font().inputStream(), "saved.ttf")
        val abandoned = repository.importFont(font().also { it[51] = 0 }.inputStream(), "abandoned.ttf")
        val staged = File(root, ".import-process-death.tmp").also { it.writeText("partial") }

        repository.pruneUnused(setOf(saved.id))

        assertTrue(File(saved.path).isFile)
        assertFalse(File(abandoned.path).exists())
        assertFalse(staged.exists())
        assertEquals(setOf("${saved.id}.ttf"), root.list()!!.toSet())
    }

    @Test fun `startup cleanup with no selection removes all owned fonts only`() {
        val root = temporaryFolder.newFolder()
        val repository = CustomFontRepository(root)
        val abandoned = repository.importFont(font().inputStream(), "abandoned.ttf")
        val unrelated = File(root, "keep.ttf").also { it.writeText("unrelated") }
        val directory = File(root, "${"1".repeat(64)}.otf").also { it.mkdir() }
        val nested = File(directory, "keep.txt").also { it.writeText("nested") }
        val unrelatedTemporary = File(root, "other.tmp").also { it.writeText("unrelated") }

        repository.pruneUnused(emptySet())

        assertFalse(File(abandoned.path).exists())
        assertTrue(unrelated.isFile)
        assertTrue(directory.isDirectory)
        assertTrue(nested.isFile)
        assertTrue(unrelatedTemporary.isFile)
    }

    @Test fun `startup cleanup rejects every invalid keep identifier before deleting files`() {
        val root = temporaryFolder.newFolder()
        val repository = CustomFontRepository(root)
        val saved = repository.importFont(font().inputStream(), "saved.ttf")
        for (id in listOf("../outside", "", "A".repeat(64), "0".repeat(63))) {
            assertEquals("invalid_font_id", failure { repository.pruneUnused(setOf(saved.id, id)) }.code)
            assertTrue(File(saved.path).isFile)
        }
    }

    @Test fun `startup cleanup never follows an owned-looking symbolic link`() {
        val root = temporaryFolder.newFolder()
        val outside = temporaryFolder.newFile("outside-prune.ttf").also { it.writeText("outside") }
        val link = File(root, "${"2".repeat(64)}.ttf").toPath()
        try {
            Files.createSymbolicLink(link, outside.toPath())
        } catch (error: Exception) {
            org.junit.Assume.assumeNoException("Symbolic links are not available on this host", error)
        }

        CustomFontRepository(root).pruneUnused(emptySet())

        assertEquals("outside", outside.readText())
    }

    @Test fun `preview resolves only existing private immutable font files`() {
        val root = temporaryFolder.newFolder()
        val repository = CustomFontRepository(root)
        val imported = repository.importFont(font().inputStream(), "sample.ttf")
        assertEquals(font().toList(), repository.withFontFile(imported.id) { it.readBytes().toList() })
        for (id in listOf("../outside", "A".repeat(64), "", "a".repeat(63))) {
            assertEquals("invalid_font_id", failure { repository.withFontFile(id) { fail("Must not render") } }.code)
        }
        assertEquals("font_unreadable", failure { repository.withFontFile("b".repeat(64)) { fail("Must not render") } }.code)
    }

    @Test fun `preview rejects directories undersized and oversized private files`() {
        val root = temporaryFolder.newFolder()
        val id = "a".repeat(64)
        val file = File(root, "$id.ttf")
        val repository = CustomFontRepository(root)
        file.mkdir()
        assertEquals("font_unreadable", failure { repository.withFontFile(id) { fail("Must not render") } }.code)
        file.delete()
        file.writeBytes(byteArrayOf(1, 2, 3))
        assertEquals("font_unreadable", failure { repository.withFontFile(id) { fail("Must not render") } }.code)
        RandomAccessFile(file, "rw").use { it.setLength(CustomFontRepository.MAX_BYTES + 1) }
        assertEquals("font_unreadable", failure { repository.withFontFile(id) { fail("Must not render") } }.code)
    }

    @Test fun `preview never follows a private font symbolic link`() {
        val root = temporaryFolder.newFolder()
        val id = "a".repeat(64)
        val outside = temporaryFolder.newFile("outside-preview.ttf").also { it.writeBytes(font()) }
        try { Files.createSymbolicLink(File(root, "$id.ttf").toPath(), outside.toPath()) }
        catch (error: Exception) { org.junit.Assume.assumeNoException("Symbolic links are not available on this host", error) }
        failure { CustomFontRepository(root).withFontFile(id) { fail("Must not render") } }
        assertArrayEquals(font(), outside.readBytes())
    }

    @Test fun `preview holds repository ownership until rendering completes`() {
        val root = temporaryFolder.newFolder()
        val repository = CustomFontRepository(root)
        val imported = repository.importFont(font().inputStream(), "sample.ttf")
        val entered = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val removeStarted = CountDownLatch(1)
        val removed = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(2)
        try {
            val render = pool.submit<Boolean> { repository.withFontFile(imported.id) {
                entered.countDown()
                assertTrue(finish.await(5, TimeUnit.SECONDS))
                it.isFile
            } }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            val remove = pool.submit { removeStarted.countDown(); repository.removeFont(imported.id); removed.countDown() }
            assertTrue(removeStarted.await(5, TimeUnit.SECONDS))
            assertFalse(removed.await(100, TimeUnit.MILLISECONDS))
            finish.countDown()
            assertTrue(render.get(5, TimeUnit.SECONDS))
            remove.get(5, TimeUnit.SECONDS)
            assertFalse(File(imported.path).exists())
        } finally { finish.countDown(); pool.shutdownNow() }
    }

    private fun font(signature: Int = 0x00010000): ByteArray = ByteArray(52).also { bytes ->
        buffer(bytes).apply {
            putInt(signature)
            putShort(2)
            putShort(32)
            putShort(1)
            putShort(0)
            putInt(0x68656164) // head
            putInt(0)
            putInt(44)
            putInt(4)
            putInt(0x636d6170) // cmap
            putInt(0)
            putInt(48)
            putInt(4)
            putInt(0x12345678)
            putInt(0x23456789)
        }
    }

    private fun buffer(bytes: ByteArray): ByteBuffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
    private fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun failure(block: () -> Unit): CustomFontException {
        try { block(); fail("Expected font operation to fail") } catch (error: CustomFontException) { return error }
        throw AssertionError("unreachable")
    }
}
