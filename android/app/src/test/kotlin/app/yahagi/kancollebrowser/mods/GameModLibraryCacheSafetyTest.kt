package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Exercise cache trust through public scans, real source files, ZIP parsing and PNG decoding. */
class GameModLibraryCacheSafetyTest {
    @get:Rule val temporary = TemporaryFolder()
    private val image = "kcs2/resources/ship/full/0001_1234.png"
    private val otherImage = "kcs2/resources/ship/full/0002_1234.png"

    @Test fun `identical trees in differently named directories share validation without sharing display names`() {
        val root = temporary.newFolder()
        write(root, "Alpha/$image", png(1))
        write(root, "Beta/$image", png(1))
        val workspace = temporary.newFolder()
        val library = GameModLibrary(GameModFileLibraryStore(root), workspace)

        val scan = library.scan()
        assertEquals(listOf("Alpha", "Beta"), scan.items.map { it["name"] })
        assertEquals(listOf("new", "duplicate"), scan.items.map { it["status"] })
        assertEquals(1, scan.items.map { it["contentHash"] }.distinct().size)
        assertEquals(1, validationCount(workspace))
        scan.items.forEach { assertSummary(it, 1, 1) }
        val accepted = library.acceptScan(scan.token)
        assertEquals("Alpha", accepted.single().name)
        assertFalse("Deduplication must not mark the skipped public directory as imported", root.resolve("Beta/.yahagi-package.json").exists())
    }

    @Test fun `identical PNG bytes at different supported relative paths are distinct validated packages`() {
        val root = temporary.newFolder()
        write(root, "First/$image", png(1))
        write(root, "Second/$otherImage", png(1))
        val workspace = temporary.newFolder()
        val library = GameModLibrary(GameModFileLibraryStore(root), workspace)

        val scan = library.scan()
        assertEquals(listOf("new", "new"), scan.items.map { it["status"] })
        assertEquals("The tree fingerprint must include each relative resource path", 2,
            scan.items.map { it["contentHash"] }.distinct().size)
        assertEquals(2, validationCount(workspace))
        assertEquals(2, library.acceptScan(scan.token).size)
    }

    @Test fun `moving validated PNG bytes to an unsupported path cannot borrow successful validation`() {
        val root = temporary.newFolder()
        val original = write(root, "ship/$image", png(1))
        val workspace = temporary.newFolder()
        val library = GameModLibrary(GameModFileLibraryStore(root), workspace)
        val warm = library.scan()
        assertSummary(warm.items.single(), 1, 1)
        library.discardScan(warm.token)
        val moved = root.resolve("ship/unrelated/portrait.png").apply { parentFile!!.mkdirs() }
        assertTrue(original.renameTo(moved))

        val scan = library.scan()
        assertEquals("invalid", scan.items.single()["status"])
        assertEquals("A different path must run the actual resource classifier", 1, validationCount(workspace))
        assertTrue(library.acceptScan(scan.token).isEmpty())
        assertFalse(root.resolve("ship/.yahagi-package.json").exists())
    }

    @Test fun `changing bytes at unchanged size and mtime then restoring them reuses only the exact old hash`() {
        val root = temporary.newFolder()
        val firstBytes = png(1)
        val secondBytes = png(2)
        assertEquals(firstBytes.size, secondBytes.size)
        val file = write(root, "ship/$image", firstBytes)
        val modified = file.lastModified()
        val workspace = temporary.newFolder()
        val library = GameModLibrary(GameModFileLibraryStore(root), workspace)
        val first = library.scan()
        val originalHash = first.items.single()["contentHash"]
        library.discardScan(first.token)

        file.writeBytes(secondBytes)
        assertTrue(file.setLastModified(modified))
        val changed = library.scan()
        assertEquals("new", changed.items.single()["status"])
        assertNotEquals(originalHash, changed.items.single()["contentHash"])
        assertEquals(1, validationCount(workspace))
        library.discardScan(changed.token)

        file.writeBytes(firstBytes)
        assertTrue(file.setLastModified(modified))
        val restored = library.scan()
        assertEquals(originalHash, restored.items.single()["contentHash"])
        assertSummary(restored.items.single(), 1, 1)
        assertEquals("The in-process success for these exact bytes remains reusable", 0, validationCount(workspace))
        assertArrayEquals(firstBytes, library.acceptScan(restored.token).single().archive.inputStream().use { source ->
            java.util.zip.ZipInputStream(source).use { zip -> zip.nextEntry; zip.readBytes() }
        })
    }

    @Test fun `normalized ZIP and equivalent raw tree have the same logical resource summary on warm and cold scans`() {
        val root = temporary.newFolder()
        // Two coordinate formats become one unmatched logical resource. An unrelated supported
        // image lets this package exercise normalization and dependency counting together.
        val normalized = linkedMapOf(
            "kcs2/img/common/icon.png" to png(1),
            "config.ini" to "[graph]\nboko_n_left=1\nboko_n_top=2\n".toByteArray(),
            "config.json" to "{\"api_mst_shipgraph\":{\"api_boko_n\":[1,2]}}".toByteArray(),
            "readme.txt" to "license retained".toByteArray(),
        )
        val raw = normalized.mapKeys { (path, _) -> "cache/" + path.replace(".png", ".hack.png") }
        val source = root.resolve("input.zip").apply { writeBytes(zip(raw)) }
        val workspace = temporary.newFolder()
        val library = GameModLibrary(GameModFileLibraryStore(root), workspace)
        val zipped = library.scan()
        assertEquals(zipped.items.toString(), "new", zipped.items.single()["status"])
        assertSummary(zipped.items.single(), 3, 1)
        val hash = zipped.items.single()["contentHash"]
        library.discardScan(zipped.token)
        assertTrue(source.delete())
        normalized.forEach { (path, bytes) -> write(root, "raw/$path", bytes) }

        val cached = library.scan()
        assertEquals(hash, cached.items.single()["contentHash"])
        assertSummary(cached.items.single(), 3, 1)
        assertEquals(0, validationCount(workspace))
        val coldWorkspace = temporary.newFolder()
        val cold = GameModLibrary(GameModFileLibraryStore(root), coldWorkspace).scan()
        assertEquals(hash, cold.items.single()["contentHash"])
        assertSummary(cold.items.single(), 3, 1)
        assertEquals(1, validationCount(coldWorkspace))
    }

    @Test fun `warm cache cannot hide a file added between copying and source recheck`() {
        changingSource(initialFiles = mapOf(image to png(1))) { root ->
            write(root, "ship/$otherImage", png(2))
        }
    }

    @Test fun `warm cache cannot hide a file deleted between copying and source recheck`() {
        changingSource(initialFiles = mapOf(image to png(1), otherImage to png(2))) { root ->
            assertTrue(root.resolve("ship/$otherImage").delete())
        }
    }

    @Test fun `warm cache cannot hide same size same mtime replacement between source passes`() {
        val old = png(1)
        val replacement = png(2)
        assertEquals(old.size, replacement.size)
        changingSource(initialFiles = mapOf(image to old)) { root ->
            val original = root.resolve("ship/$image")
            val modified = original.lastModified()
            val temporaryReplacement = root.resolve("replacement.tmp").apply { writeBytes(replacement) }
            assertTrue(temporaryReplacement.setLastModified(modified))
            Files.move(temporaryReplacement.toPath(), original.toPath(), StandardCopyOption.REPLACE_EXISTING)
            assertEquals(old.size.toLong(), original.length())
            assertEquals(modified, original.lastModified())
        }
    }

    private fun changingSource(initialFiles: Map<String, ByteArray>, change: (File) -> Unit) {
        val root = temporary.newFolder()
        initialFiles.forEach { (path, bytes) -> write(root, "ship/$path", bytes) }
        val workspace = temporary.newFolder()
        val store = BetweenPassesStore(GameModFileLibraryStore(root))
        val library = GameModLibrary(store, workspace)
        val warm = library.scan()
        assertEquals("new", warm.items.single()["status"])
        library.discardScan(warm.token)
        store.afterNextReadSession = { change(root) }

        val changed = library.scan()
        assertNull("The deterministic mutation hook must have run after the first pass", store.afterNextReadSession)
        assertEquals("invalid", changed.items.single()["status"])
        assertTrue((changed.items.single()["error"] as String).contains("发生变化"))
        assertEquals("Source recheck must reject before reaching the warm validation cache", 0, validationCount(workspace))
        assertTrue(library.acceptScan(changed.token).isEmpty())
        assertFalse(root.resolve("ship/.yahagi-package.json").exists())
    }

    private class BetweenPassesStore(private val delegate: GameModLibraryStore) : GameModLibraryStore by delegate {
        var afterNextReadSession: (() -> Unit)? = null
        override fun <T> withReadSession(block: () -> T): T {
            val result = delegate.withReadSession(block)
            val change = afterNextReadSession
            afterNextReadSession = null
            change?.invoke()
            return result
        }
    }

    private fun write(root: File, path: String, bytes: ByteArray): File = root.resolve(path).apply {
        parentFile!!.mkdirs(); writeBytes(bytes)
    }
    private fun validationCount(workspace: File) = workspace.walkTopDown().count { it.isDirectory && it.name == "validate" }
    private fun assertSummary(item: Map<String, Any?>, resources: Int, supported: Int) {
        assertEquals(resources, item["resourceCount"])
        assertEquals(supported, item["supportedCount"])
    }
    private fun zip(files: Map<String, ByteArray>): ByteArray = ByteArrayOutputStream().also { output ->
        ZipOutputStream(output).use { zip -> files.forEach { (path, bytes) ->
            zip.putNextEntry(ZipEntry(path)); zip.write(bytes); zip.closeEntry()
        } }
    }.toByteArray()

    private fun png(value: Int): ByteArray = ByteArrayOutputStream().also { output ->
        val data = DataOutputStream(output)
        data.write(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
        fun chunk(name: String, bytes: ByteArray) {
            val tag = name.toByteArray()
            data.writeInt(bytes.size); data.write(tag); data.write(bytes)
            data.writeInt(CRC32().also { it.update(tag); it.update(bytes) }.value.toInt())
        }
        chunk("IHDR", ByteArrayOutputStream().also { DataOutputStream(it).apply {
            writeInt(1); writeInt(1); write(byteArrayOf(8, 6, 0, 0, 0))
        } }.toByteArray())
        chunk("IDAT", ByteArrayOutputStream().also { compressed -> DeflaterOutputStream(compressed).use {
            it.write(byteArrayOf(0, value.toByte(), 0, 0, -1))
        } }.toByteArray())
        chunk("IEND", byteArrayOf())
    }.toByteArray()
}
