package app.yahagi.kancollebrowser.mods

import com.google.gson.JsonParser
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.io.FilterOutputStream
import java.io.OutputStream
import java.nio.file.Files
import java.util.UUID
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class GameModLibraryAuditRegressionTest {
    @get:Rule val temporary = TemporaryFolder()
    private val asset = "kcs2/resources/ship/full/0001_1234_secret.png"

    @Test fun `ZIP update preserves an old tree edited after preview and leaves repository unchanged`() {
        val public = temporary.newFolder()
        val source = File(public, "manual.zip").apply { writeBytes(archive(1)) }
        val library = GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder())
        val first = library.acceptScan(library.scan().token).single()
        val repository = GameModRepository(temporary.newFolder())
        val imported = first.archive.inputStream().use { repository.preflightLibrary(it, "Legacy.zip") }
        repository.commitLibraryImport(imported["token"] as String, first.id, first.contentHash)
        val before = repository.status()
        val coordinator = GameModLibraryCoordinator(repository, library, temporary.newFolder())
        source.writeBytes(archive(2))
        val preview = coordinator.scan()
        val edited = File(public, "${first.path}/$asset").apply { writeBytes(png(3)) }

        expectCode("library_changed") { coordinator.commitScan(preview["token"] as String) }

        assertArrayEquals(png(3), edited.readBytes())
        assertTrue(source.isFile)
        assertEquals(before, repository.status())
        assertEquals(first.path, (library.status()["packages"] as List<*>).single().let { (it as Map<*, *>)["path"] })
    }

    @Test fun `ZIP update rejects marker replacement after preview without changing its ownership`() {
        val public = temporary.newFolder()
        val source = File(public, "manual.zip").apply { writeBytes(archive(1)) }
        val library = GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder())
        val first = library.acceptScan(library.scan().token).single()
        source.writeBytes(archive(2))
        val preview = library.scan()
        val marker = File(public, "${first.path}/.yahagi-package.json")
        val replacement = JsonParser.parseString(marker.readText()).asJsonObject.apply { addProperty("id", UUID.randomUUID().toString()) }.toString()
        marker.writeText(replacement)

        expectCode("library_changed") { library.acceptScan(preview.token) }

        assertEquals(replacement, marker.readText())
        assertTrue(source.exists())
        assertEquals(1, public.listFiles()!!.count { it.isDirectory && !it.name.startsWith(".yahagi-") })
    }

    @Test fun `ZIP update checks old files again after staging before replacing their directory`() {
        val public = temporary.newFolder()
        val source = File(public, "manual.zip").apply { writeBytes(archive(1)) }
        val files = GameModFileLibraryStore(public)
        var editDuringPublication: (() -> Unit)? = null
        val store = object : GameModLibraryStore by files {
            override fun rename(from: String, to: String): Boolean {
                editDuringPublication?.also { editDuringPublication = null }?.invoke()
                return files.rename(from, to)
            }
        }
        val library = GameModLibrary(store, temporary.newFolder())
        val first = library.acceptScan(library.scan().token).single()
        source.writeBytes(archive(2))
        val preview = library.scan()
        val edited = File(public, "${first.path}/$asset")
        editDuringPublication = { edited.writeBytes(png(3)) }

        expectCode("library_changed") { library.acceptScan(preview.token) }

        assertArrayEquals(png(3), edited.readBytes())
        assertEquals(first.path, (library.status()["packages"] as List<*>).single().let { (it as Map<*, *>)["path"] })
    }

    @Test fun `late edit during index publication preserves old files and restores old public record`() =
        assertLateIndexEditRejected()

    @Test fun `late edit of a markerless old tree rejects replacement and restores old public record`() =
        assertLateIndexEditRejected(markerless = true)

    @Test fun `old directory recreated during index publication rejects replacement and restores old public record`() =
        assertLateIndexEditRejected(missing = true)

    @Test fun `late edit during same content ZIP publication rejects replacement and restores old public record`() =
        assertLateIndexEditRejected(repacked = true)

    private fun assertLateIndexEditRejected(markerless: Boolean = false, missing: Boolean = false, repacked: Boolean = false) {
        val public = temporary.newFolder()
        val source = File(public, "manual.zip").apply { writeBytes(archive(1)) }
        val files = GameModFileLibraryStore(public)
        var editDuringIndex: (() -> Unit)? = null
        val store = object : GameModLibraryStore by files {
            override fun openWrite(relative: String): OutputStream {
                val output = files.openWrite(relative)
                if (relative !in listOf("library.json", ".yahagi-library-backup.json")) return output
                return object : FilterOutputStream(output) {
                    override fun write(bytes: ByteArray, offset: Int, length: Int) = out.write(bytes, offset, length)
                    override fun close() {
                        super.close()
                        editDuringIndex?.also { editDuringIndex = null }?.invoke()
                    }
                }
            }
        }
        val library = GameModLibrary(store, temporary.newFolder())
        val first = library.acceptScan(library.scan().token).single()
        if (markerless) File(public, "${first.path}/.yahagi-package.json").delete()
        if (missing) File(public, first.path).deleteRecursively()
        source.writeBytes(if (repacked) archive(1, "repacked") else archive(2))
        val preview = library.scan()
        val edited = File(public, "${first.path}/$asset")
        editDuringIndex = { edited.parentFile.mkdirs(); edited.writeBytes(png(3)) }

        expectCode("library_changed") { library.acceptScan(preview.token) }

        assertArrayEquals(png(3), edited.readBytes())
        assertTrue(source.isFile)
        for (instance in listOf(library, GameModLibrary(files, temporary.newFolder()))) {
            assertEquals(first.path, (instance.status()["packages"] as List<*>).single().let { (it as Map<*, *>)["path"] })
        }
    }

    @Test fun `late replacement rollback retains earlier successful packages in the same batch`() {
        val public = temporary.newFolder()
        val sourceA = File(public, "a.zip").apply { writeBytes(archive(1)) }
        val sourceB = File(public, "b.zip").apply { writeBytes(archive(2)) }
        val files = GameModFileLibraryStore(public)
        var writesUntilEdit = 0
        var edited: File? = null
        val store = object : GameModLibraryStore by files {
            override fun openWrite(relative: String): OutputStream {
                val output = files.openWrite(relative)
                if (relative !in listOf("library.json", ".yahagi-library-backup.json")) return output
                return object : FilterOutputStream(output) {
                    override fun write(bytes: ByteArray, offset: Int, length: Int) = out.write(bytes, offset, length)
                    override fun close() {
                        super.close()
                        if (writesUntilEdit > 0 && --writesUntilEdit == 0) edited!!.writeBytes(png(5))
                    }
                }
            }
        }
        val library = GameModLibrary(store, temporary.newFolder())
        val first = library.acceptScan(library.scan().token)
        val oldA = first.single { it.name == "a" }
        val oldB = first.single { it.name == "b" }
        sourceA.writeBytes(archive(3)); sourceB.writeBytes(archive(4))
        val preview = library.scan()
        edited = File(public, "${oldB.path}/$asset")
        writesUntilEdit = 2

        expectCode("library_changed") { library.acceptScan(preview.token) }

        assertArrayEquals(png(5), edited.readBytes())
        for (instance in listOf(library, GameModLibrary(files, temporary.newFolder()))) {
            val records = (instance.status()["packages"] as List<*>).filterIsInstance<Map<*, *>>().associateBy { it["id"] }
            assertNotEquals(oldA.contentHash, records[oldA.id]!!["contentHash"])
            assertNotEquals(oldA.path, records[oldA.id]!!["path"])
            assertEquals(oldB.path, records[oldB.id]!!["path"])
        }
    }

    @Test fun `unchanged old tree is replaced and retained ZIP consumed after normal update`() {
        val public = temporary.newFolder()
        val source = File(public, "manual.zip").apply { writeBytes(archive(1)) }
        val library = GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder())
        val first = library.acceptScan(library.scan().token).single()
        source.writeBytes(archive(2))
        val preview = library.scan()
        val updated = library.acceptScan(preview.token).single()

        assertEquals(first.id, updated.id)
        assertFalse(File(public, first.path).exists())
        assertArrayEquals(png(2), File(public, "${updated.path}/$asset").readBytes())
        assertTrue(library.completeScan(preview.token).isEmpty())
        assertFalse(source.exists())
    }

    @Test fun `same content repacked ZIP still completes an ordinary confirmed update`() {
        val public = temporary.newFolder()
        val source = File(public, "manual.zip").apply { writeBytes(archive(1)) }
        val library = GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder())
        val first = library.acceptScan(library.scan().token).single()
        source.writeBytes(archive(1, "repacked"))
        val preview = library.scan()

        val updated = library.acceptScan(preview.token).single()

        assertEquals(first.id, updated.id)
        assertEquals(first.contentHash, updated.contentHash)
        assertEquals("updated", updated.status)
        assertArrayEquals(png(1), File(public, "${updated.path}/$asset").readBytes())
        assertTrue(library.completeScan(preview.token).isEmpty())
        assertFalse(source.exists())
    }

    @Test fun `large applied configuration survives backup reload and synchronization journal recovery`() {
        val public = temporary.newFolder()
        val library = GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder())
        val config = mapOf("schemaVersion" to 1, "order" to listOf("saved"), "resourceMetadata" to "x".repeat(4 * 1024 * 1024))
        library.saveAppliedConfiguration(config)
        assertTrue(File(public, "library.json").length() > 4L * 1024 * 1024)
        val reloaded = GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder())
        assertEquals(config, reloaded.appliedConfiguration()!!.mapValues { (key, value) -> if (key == "schemaVersion") (value as Number).toInt() else value })
        val sync = temporary.newFolder()
        val journal = File(sync, "pending-public-sync.json").apply {
            writeText(com.google.gson.Gson().toJson(mapOf("removedIds" to emptyList<String>(), "configuration" to config)))
        }
        val coordinator = GameModLibraryCoordinator(GameModRepository(temporary.newFolder()), reloaded, sync)

        coordinator.retryPending()

        assertFalse(journal.exists())
        assertNull(coordinator.status()["error"])
        val preview = coordinator.scan()
        coordinator.discardScan(preview["token"] as String)
        assertEquals(config["resourceMetadata"], GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder()).appliedConfiguration()!!["resourceMetadata"])
    }

    @Test fun `over budget applied state is rejected before either rotating backup is overwritten`() {
        val public = temporary.newFolder()
        val library = GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder())
        library.saveAppliedConfiguration(mapOf("order" to listOf("first")))
        library.saveAppliedConfiguration(mapOf("order" to listOf("second")))
        val slots = public.listFiles()!!.filter { it.name.endsWith(".json") }.associate { it.name to it.readBytes() }

        expectCode("quota_exceeded") {
            // JSON control-character escaping crosses the byte budget without
            // retaining another 64 MiB input string throughout serialization.
            library.saveAppliedConfiguration(mapOf("resourceMetadata" to "\u0001".repeat(64 * 1024 * 1024 / 6 + 1)))
        }

        slots.forEach { (name, bytes) -> assertArrayEquals(bytes, File(public, name).readBytes()) }
        assertEquals(listOf("second"), library.appliedConfiguration()!!["order"])
        assertEquals(listOf("second"), GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder()).appliedConfiguration()!!["order"])
    }

    @Test fun `picker names with percent and hash preserve display names and publish safe directories`() {
        for (name in listOf("100%", "Ship#1")) {
            val public = temporary.newFolder()
            val repository = GameModRepository(temporary.newFolder())
            val library = GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder())
            val coordinator = GameModLibraryCoordinator(repository, library, temporary.newFolder())
            val preview = archive(1).inputStream().use { repository.preflight(it, "$name.zip") }

            coordinator.commitImport(preview["token"] as String)

            val saved = (library.status()["packages"] as List<*>).single() as Map<*, *>
            assertEquals(name, saved["name"])
            assertFalse((saved["path"] as String).any { it == '%' || it == '#' })
            assertArrayEquals(png(1), File(public, "${saved["path"]}/$asset").readBytes())
            val scan = coordinator.scan()
            assertEquals("unchanged", ((scan["entries"] as List<*>).single() as Map<*, *>)["kind"])
            coordinator.discardScan(scan["token"] as String)
        }
    }

    @Test fun `unsupported root names are invalid entries while healthy packages keep scanning`() {
        val public = temporary.newFolder()
        File(public, "Ship/$asset").apply { parentFile.mkdirs(); writeBytes(png(1)) }
        File(public, "backup#1").mkdir()
        File(public, "100%.zip").writeBytes(archive(2))
        val library = GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder())

        val preview = library.scan()

        assertEquals("new", preview.items.single { it["path"] == "Ship" }["status"])
        assertEquals(setOf("backup#1", "100%.zip"), preview.items.filter { it["status"] == "invalid" }.map { it["path"] }.toSet())
        val accepted = library.acceptScan(preview.token).single()
        assertEquals("Ship", accepted.path)
        assertTrue(File(public, "backup#1").exists())
        assertTrue(File(public, "100%.zip").exists())
    }

    @Test fun `unsupported root names from a document provider are isolated before any file access`() {
        val public = temporary.newFolder()
        File(public, "Ship/$asset").apply { parentFile.mkdirs(); writeBytes(png(1)) }
        val files = GameModFileLibraryStore(public)
        val store = object : GameModLibraryStore by files {
            override fun list(relative: String): List<GameModLibraryEntry> = files.list(relative) +
                if (relative.isEmpty()) listOf(GameModLibraryEntry("backup#1", true), GameModLibraryEntry("other/child.zip", false)) else emptyList()
        }
        val library = GameModLibrary(store, temporary.newFolder())

        val preview = library.scan()

        assertEquals(2, preview.items.count { it["status"] == "invalid" })
        assertEquals("Ship", library.acceptScan(preview.token).single().path)
    }

    @Test fun `local tree validation still rejects unsupported names and symbolic links`() {
        val public = temporary.newFolder()
        val tree = temporary.newFolder()
        File(tree, asset).apply { parentFile.mkdirs(); writeBytes(png(1)) }
        val library = GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder())
        val unsupported = File(tree, "backup#1.txt").apply { writeText("keep") }
        expectCode("unsafe_path") { library.fingerprintLocalTree(tree) }
        unsupported.delete()
        val outside = temporary.newFile().apply { writeText("outside") }
        val link = File(tree, "linked.txt").toPath()
        try { Files.createSymbolicLink(link, outside.toPath()) }
        catch (error: Exception) { org.junit.Assume.assumeNoException("Symbolic links are unavailable on this host", error) }
        expectCode("unsafe_path") { library.fingerprintLocalTree(tree) }
        expectCode("unsafe_path") { GameModFileLibraryStore(tree).openRead("linked.txt") }
        assertEquals("outside", outside.readText())
    }

    @Test fun `package marker keeps its smaller budget after applied state budget increases`() {
        val public = temporary.newFolder()
        val tree = temporary.newFolder()
        File(tree, asset).apply { parentFile.mkdirs(); writeBytes(png(1)) }
        val library = GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder())
        val saved = library.savePackage(UUID.randomUUID().toString(), "Ship", tree)
        val marker = File(public, "${saved["path"]}/.yahagi-package.json")
        val payload = JsonParser.parseString(marker.readText()).asJsonObject.apply { addProperty("padding", "x".repeat(4 * 1024 * 1024)) }
        marker.writeText(payload.toString())

        val preview = library.scan()

        assertEquals("invalid", preview.items.single()["status"])
        assertTrue(library.acceptScan(preview.token).isEmpty())
        assertTrue(marker.length() > 4L * 1024 * 1024)
    }

    @Test fun `oversized synchronization journal is rejected before parsing and kept for recovery`() {
        val public = temporary.newFolder()
        val sync = temporary.newFolder()
        val journal = File(sync, "pending-public-sync.json")
        RandomAccessFile(journal, "rw").use { it.setLength(64L * 1024 * 1024 + 1) }
        val coordinator = GameModLibraryCoordinator(GameModRepository(temporary.newFolder()),
            GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder()), sync)

        expectCode("library_metadata_invalid") { coordinator.retryPending() }

        assertEquals(64L * 1024 * 1024 + 1, journal.length())
        assertTrue(public.listFiles()!!.isEmpty())
    }

    private fun expectCode(code: String, block: () -> Unit) {
        val error = runCatching(block).exceptionOrNull()
        assertEquals(code, (error as? GameModException)?.code)
    }

    private fun archive(value: Int, comment: String? = null): ByteArray = ByteArrayOutputStream().also { output ->
        ZipOutputStream(output).use { zip ->
            if (comment != null) zip.setComment(comment)
            zip.putNextEntry(ZipEntry(asset)); zip.write(png(value)); zip.closeEntry()
        }
    }.toByteArray()

    private fun png(value: Int): ByteArray = ByteArrayOutputStream().also { output ->
        val writer = DataOutputStream(output)
        writer.write(byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
        fun chunk(type: String, bytes: ByteArray) {
            val tag = type.toByteArray(); writer.writeInt(bytes.size); writer.write(tag); writer.write(bytes)
            writer.writeInt(CRC32().also { it.update(tag); it.update(bytes) }.value.toInt())
        }
        chunk("IHDR", ByteArrayOutputStream().also { DataOutputStream(it).apply { writeInt(1); writeInt(1); write(byteArrayOf(8, 6, 0, 0, 0)) } }.toByteArray())
        chunk("IDAT", ByteArrayOutputStream().also { DeflaterOutputStream(it).use { deflater -> deflater.write(byteArrayOf(0, value.toByte(), 0, 0, 0xff.toByte())) } }.toByteArray())
        chunk("IEND", byteArrayOf())
    }.toByteArray()
}
