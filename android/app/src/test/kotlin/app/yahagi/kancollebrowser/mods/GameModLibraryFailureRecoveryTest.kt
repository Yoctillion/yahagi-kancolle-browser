package app.yahagi.kancollebrowser.mods

import com.google.gson.Gson
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Faults cross the public-store boundary; parsing, persistence and serving use real files. */
class GameModLibraryFailureRecoveryTest {
    @get:Rule val temporary = TemporaryFolder()
    private val resource = "kcs2/resources/ship/banner/0001_1234.png"
    private val gson = Gson()

    @Test fun `ZIP stream failing after delivered bytes cannot import partial content and can be retried`() {
        val fixture = fixture()
        val source = fixture.public.resolve("new.zip").apply { writeBytes(zip(mapOf(resource to png(2)))) }
        val publicBefore = sourceFiles(fixture.public)
        val repositoryBefore = repositoryState(fixture.repository)
        fixture.store.failRead = source.name

        val scan = fixture.coordinator.scan()
        assertEquals("invalid", entries(scan).single { it["path"] == source.name }["kind"])
        assertTrue("The source delivered data before the injected IOException", fixture.store.deliveredBeforeFailure > 0)
        fixture.coordinator.commitScan(token(scan))
        assertEquals(publicBefore, sourceFiles(fixture.public))
        assertEquals(repositoryBefore, repositoryState(fixture.repository))
        assertArrayEquals(png(1), read(fixture.repository))

        commitFreshScan(fixture)
        assertFalse(source.exists())
        assertEquals(2, packages(fixture.repository).size)
        assertArrayEquals(png(1), read(fixture.repository))
    }

    @Test fun `existing tree stream failure retains identity and applied bytes until a fresh import succeeds`() {
        val fixture = fixture()
        val record = packages(fixture.repository).single()
        val image = fixture.public.walkTopDown().single { it.isFile && it.extension == "png" }
        image.writeBytes(png(2))
        fixture.store.failRead = image.relativeTo(fixture.public).invariantSeparatorsPath
        val publicBefore = files(fixture.public)
        val repositoryBefore = repositoryState(fixture.repository)

        val scan = fixture.coordinator.scan()
        val entry = entries(scan).single()
        assertEquals(record["id"], entry["id"])
        assertEquals("invalid", entry["kind"])
        fixture.coordinator.discardScan(token(scan))
        assertEquals(publicBefore, files(fixture.public))
        assertEquals(repositoryBefore, repositoryState(fixture.repository))
        assertArrayEquals(png(1), read(fixture.repository))

        commitFreshScan(fixture)
        assertEquals(listOf(record["id"]), packages(fixture.repository).map { it["id"] })
        assertEquals(true, fixture.repository.status()["pending"])
        assertArrayEquals(png(1), read(fixture.repository))
        fixture.repository.finishApply(fixture.repository.applyDraft())
        assertArrayEquals(png(2), read(GameModRepository(fixture.repositoryRoot)))
    }

    @Test fun `nested listing error is invalid rather than missing and does not rewrite the source marker`() {
        val fixture = fixture()
        val folder = fixture.public.listFiles()!!.single { it.isDirectory }
        fixture.store.failList = "${folder.name}/kcs2/resources"
        val publicBefore = files(fixture.public)
        val repositoryBefore = repositoryState(fixture.repository)

        val scan = fixture.coordinator.scan()
        assertEquals(listOf("invalid"), entries(scan).map { it["kind"] })
        assertEquals(packages(fixture.repository).single()["id"], entries(scan).single()["id"])
        fixture.coordinator.discardScan(token(scan))
        assertEquals(publicBefore, files(fixture.public))
        assertEquals(repositoryBefore, repositoryState(fixture.repository))
        commitFreshScan(fixture)
        assertEquals(repositoryBefore, repositoryState(fixture.repository))
        assertArrayEquals(png(1), read(fixture.repository))
    }

    @Test fun `root listing exception cannot turn an existing library into an empty import`() {
        val fixture = fixture()
        val publicBefore = files(fixture.public)
        val repositoryBefore = repositoryState(fixture.repository)
        fixture.store.failList = ""

        assertTrue(runCatching { fixture.coordinator.scan() }.exceptionOrNull() is IOException)
        assertEquals(publicBefore, files(fixture.public))
        assertEquals(repositoryBefore, repositoryState(fixture.repository))
        val retry = fixture.coordinator.scan()
        assertEquals(listOf("unchanged"), entries(retry).map { it["kind"] })
        fixture.coordinator.commitScan(token(retry))
        assertEquals(repositoryBefore, repositoryState(fixture.repository))
    }

    @Test fun `staged resource openWrite failure preserves ZIP and applied session and permits a clean retry`() {
        val fixture = fixture()
        val source = fixture.public.resolve("new.zip").apply { writeBytes(zip(mapOf(resource to png(2)))) }
        val scan = fixture.coordinator.scan()
        val publicBefore = sourceFiles(fixture.public)
        val repositoryBefore = repositoryState(fixture.repository)
        fixture.store.failWrite = { it.startsWith(".yahagi-import-") && it.endsWith(".png") }

        assertCode("storage_error") { fixture.coordinator.commitScan(token(scan)) }
        assertEquals(publicBefore, sourceFiles(fixture.public))
        assertEquals(repositoryBefore, repositoryState(fixture.repository))
        assertArrayEquals(png(1), read(fixture.repository))
        assertCode("invalid_token") { fixture.coordinator.commitScan(token(scan)) }
        commitFreshScan(fixture)
        assertFalse(source.exists())
        assertEquals(2, packages(fixture.repository).size)
        assertArrayEquals(png(1), read(fixture.repository))
    }

    @Test fun `provider rename exception cannot consume ZIP or change repository and a later scan recovers`() {
        val fixture = fixture()
        val source = fixture.public.resolve("new.zip").apply { writeBytes(zip(mapOf(resource to png(2)))) }
        val scan = fixture.coordinator.scan()
        val publicBefore = sourceFiles(fixture.public)
        val repositoryBefore = repositoryState(fixture.repository)
        fixture.store.failRename = true

        assertCode("storage_error") { fixture.coordinator.commitScan(token(scan)) }
        assertEquals(publicBefore, sourceFiles(fixture.public))
        assertEquals(repositoryBefore, repositoryState(fixture.repository))
        commitFreshScan(fixture)
        assertFalse(source.exists())
        assertEquals(2, packages(fixture.repository).size)
        assertArrayEquals(png(1), read(fixture.repository))
    }

    @Test fun `failed rename fallback must not leave an unpublished partial package visible to later scans`() {
        val fixture = fixture()
        val source = fixture.public.resolve("new.zip").apply { writeBytes(zip(mapOf(resource to png(2)))) }
        val scan = fixture.coordinator.scan()
        val directoriesBefore = fixture.public.listFiles()!!.filter { it.isDirectory }.map { it.name }.toSet()
        val publicBefore = sourceFiles(fixture.public)
        val repositoryBefore = repositoryState(fixture.repository)
        fixture.store.renameUnsupported = true
        fixture.store.failWrite = { !it.startsWith(".") && it.endsWith(".png") }

        assertCode("storage_error") { fixture.coordinator.commitScan(token(scan)) }
        assertEquals(publicBefore, sourceFiles(fixture.public))
        assertEquals(repositoryBefore, repositoryState(fixture.repository))
        assertEquals("Unverified fallback directories must be removed before another scan",
            directoriesBefore, fixture.public.listFiles()!!.filter { it.isDirectory }.map { it.name }.toSet())
        commitFreshScan(fixture)
        assertFalse(source.exists())
        val after = fixture.coordinator.scan()
        assertEquals(listOf("unchanged", "unchanged"), entries(after).map { it["kind"] }.sortedBy { it.toString() })
        fixture.coordinator.discardScan(token(after))
        assertArrayEquals(png(1), read(fixture.repository))
    }

    @Test fun `picker save failure keeps reusable preflight and leaves original external ZIP and applied bytes intact`() {
        val fixture = fixture()
        val source = temporary.newFile("picker.zip").apply { writeBytes(zip(mapOf(resource to png(2)))) }
        val sourceBefore = source.readBytes()
        val preview = source.inputStream().use { fixture.repository.preflight(it, source.name) }
        val publicBefore = files(fixture.public)
        val repositoryBefore = repositoryState(fixture.repository)
        fixture.store.failWrite = { it.endsWith(".png") }

        assertCode("storage_error") { fixture.coordinator.commitImport(preview["token"] as String) }
        assertArrayEquals(sourceBefore, source.readBytes())
        assertEquals(publicBefore, files(fixture.public))
        assertEquals(repositoryBefore, repositoryState(fixture.repository))
        fixture.coordinator.commitImport(preview["token"] as String)
        assertArrayEquals(sourceBefore, source.readBytes())
        assertEquals(2, packages(fixture.repository).size)
        assertArrayEquals(png(1), read(fixture.repository))
    }

    @Test fun `undeletable rename fallback with one valid PNG cannot become a partial import`() {
        val fixture = fixture()
        val second = "kcs2/resources/ship/full/0002_1234.png"
        val source = fixture.public.resolve("incomplete.zip").apply {
            writeBytes(zip(linkedMapOf(resource to png(2), second to png(3))))
        }
        val originalArchive = source.readBytes()
        val existingDirectories = fixture.public.listFiles()!!.filter { it.isDirectory }.map { it.name }.toSet()
        val repositoryBefore = repositoryState(fixture.repository)
        val scan = fixture.coordinator.scan()
        fixture.store.renameUnsupported = true
        fixture.store.protectFailedWriteRoot = true
        fixture.store.refuseDeleteChildren = true
        fixture.store.failWrite = { !it.startsWith(".") && it.endsWith(second) }

        assertCode("storage_error") { fixture.coordinator.commitScan(token(scan)) }
        val partial = fixture.public.listFiles()!!.single {
            it.isDirectory && it.name !in existingDirectories && it.resolve(resource).isFile
        }
        assertArrayEquals("The first complete valid PNG was published before the next file failed", png(2), partial.resolve(resource).readBytes())
        assertFalse(partial.resolve(second).exists())
        assertArrayEquals(originalArchive, source.readBytes())
        assertEquals(repositoryBefore, repositoryState(fixture.repository))

        val retry = fixture.coordinator.scan()
        assertTrue("A leftover subset is never an independently importable package",
            entries(retry).none { it["path"] == partial.name && it["kind"] in listOf("new", "updated", "unchanged") })
        assertEquals("new", entries(retry).single { it["path"] == source.name }["kind"])
        fixture.coordinator.discardScan(token(retry))
        assertArrayEquals("A scan with a leftover partial tree must preserve the complete source ZIP", originalArchive, source.readBytes())
        assertEquals(repositoryBefore, repositoryState(fixture.repository))

        fixture.store.refuseDeleteRoots.clear()
        val confirmed = fixture.coordinator.scan()
        fixture.coordinator.commitScan(token(confirmed))
        assertFalse(source.exists())
        assertEquals(2, packages(fixture.repository).size)
        val imported = packages(fixture.repository).single { it["name"] == "incomplete" }
        val importedPaths = (imported["resources"] as List<*>).map { (it as Map<*, *>)["path"] }.toSet()
        assertEquals(setOf(resource, second), importedPaths)
        assertArrayEquals(png(1), read(fixture.repository))
    }

    @Test fun `discarding and evicting previews preserves root ZIP public tree and active resource bytes`() {
        val fixture = fixture()
        val source = fixture.public.resolve("new.zip").apply { writeBytes(zip(mapOf(resource to png(2)))) }
        val publicBefore = files(fixture.public)
        val repositoryBefore = repositoryState(fixture.repository)
        val scans = List(3) { fixture.coordinator.scan() }

        assertCode("invalid_token") { fixture.coordinator.commitScan(token(scans.first())) }
        scans.drop(1).forEach { fixture.coordinator.discardScan(token(it)) }
        assertTrue(source.exists())
        assertEquals(publicBefore, files(fixture.public))
        assertEquals(repositoryBefore, repositoryState(fixture.repository))
        assertArrayEquals(png(1), read(fixture.repository))
        commitFreshScan(fixture)
        assertFalse(source.exists())
        assertEquals(2, packages(fixture.repository).size)
    }

    @Test fun `non atomic deletion cannot erase partial package guard before locked resources are removed`() {
        val fixture = fixture()
        val second = "kcs2/resources/ship/full/0002_1234.png"
        val source = fixture.public.resolve("locked.zip").apply {
            writeBytes(zip(linkedMapOf(resource to png(2), second to png(3))))
        }
        val originalArchive = source.readBytes()
        val existingDirectories = fixture.public.listFiles()!!.filter { it.isDirectory }.map { it.name }.toSet()
        val repositoryBefore = repositoryState(fixture.repository)
        val scan = fixture.coordinator.scan()
        fixture.store.renameUnsupported = true
        fixture.store.protectFailedWriteRoot = true
        fixture.store.stripMarkerOnRefusedRootDelete = true
        fixture.store.refuseDeleteChildren = true
        fixture.store.failWrite = { !it.startsWith(".") && it.endsWith(second) }

        assertCode("storage_error") { fixture.coordinator.commitScan(token(scan)) }
        val partial = fixture.public.listFiles()!!.single {
            it.isDirectory && it.name !in existingDirectories && it.resolve(resource).isFile
        }
        assertArrayEquals(png(2), partial.resolve(resource).readBytes())
        assertFalse(partial.resolve(second).exists())
        assertArrayEquals(originalArchive, source.readBytes())
        assertEquals(repositoryBefore, repositoryState(fixture.repository))

        // Reopening loses every in-memory hint that this public directory was never complete.
        val reopened = GameModLibraryCoordinator(fixture.repository,
            GameModLibrary(fixture.store, temporary.newFolder()), temporary.newFolder())
        val unexpected = mutableListOf<String>()
        for ((name, coordinator) in listOf("current" to fixture.coordinator, "reopened" to reopened)) {
            val preview = coordinator.scan()
            entries(preview).filter { it["path"] == partial.name && it["kind"] in listOf("new", "updated", "unchanged") }
                .forEach { unexpected.add("$name:${it["kind"]}") }
            assertEquals("The complete archive remains separately available after $name scan", "new",
                entries(preview).single { it["path"] == source.name }["kind"])
            coordinator.discardScan(token(preview))
            assertArrayEquals(originalArchive, source.readBytes())
            assertEquals(repositoryBefore, repositoryState(fixture.repository))
        }
        assertArrayEquals(png(1), read(fixture.repository))
        assertTrue("Partial content became importable after cleanup removed its guard: $unexpected", unexpected.isEmpty())
    }

    @Test fun `confirmation rejects added removed and renamed members even with restored timestamps`() {
        for (mutation in listOf("add", "remove", "rename")) {
            val fixture = fixture()
            val folder = fixture.public.listFiles()!!.single { it.isDirectory }
            val note = folder.resolve("notes/old.txt").apply { parentFile!!.mkdirs(); writeText("preserve me") }
            // Import the sidecar first, then preview exactly the source that will be mutated.
            commitFreshScan(fixture)
            fixture.repository.finishApply(fixture.repository.applyDraft())
            val scan = fixture.coordinator.scan()
            val timestamps = folder.walkTopDown().associateWith { it.lastModified() }
            when (mutation) {
                "add" -> note.parentFile.resolve("new.txt").writeText("preserve me")
                "remove" -> assertTrue(note.delete())
                "rename" -> assertTrue(note.renameTo(note.parentFile.resolve("renamed.txt")))
            }
            timestamps.forEach { (file, timestamp) -> if (file.exists()) assertTrue(file.setLastModified(timestamp)) }
            val renamed = note.parentFile.resolve("renamed.txt")
            if (renamed.exists()) assertTrue(renamed.setLastModified(timestamps.getValue(note)))
            timestamps.forEach { (file, timestamp) -> if (file.exists()) assertEquals(timestamp, file.lastModified()) }
            val publicAfterEdit = files(fixture.public)
            val repositoryBefore = repositoryState(fixture.repository)

            assertCode("library_changed") { fixture.coordinator.commitScan(token(scan)) }
            assertEquals("Source edit must survive rejected confirmation: $mutation", publicAfterEdit, files(fixture.public))
            assertEquals("Repository must stay unchanged: $mutation", repositoryBefore, repositoryState(fixture.repository))
            assertArrayEquals(png(1), read(fixture.repository))
            commitFreshScan(fixture)
            assertEquals(1, packages(fixture.repository).size)
            assertEquals(true, fixture.repository.status()["pending"])
            assertArrayEquals(png(1), read(fixture.repository))
        }
    }

    private fun fixture(): Fixture {
        val public = temporary.newFolder()
        val store = FaultStore(GameModFileLibraryStore(public))
        val repositoryRoot = temporary.newFolder()
        val repository = GameModRepository(repositoryRoot)
        val library = GameModLibrary(store, temporary.newFolder())
        val coordinator = GameModLibraryCoordinator(repository, library, temporary.newFolder())
        val preview = repository.preflight(zip(mapOf(resource to png(1))).inputStream(), "active.zip")
        coordinator.commitImport(preview["token"] as String)
        val pack = packages(repository).single()
        val resources = pack["resources"] as List<*>
        repository.saveDraft(mapOf("master" to true, "order" to listOf(pack["id"]),
            "enabledPackages" to listOf(pack["id"]), "enabledResources" to resources.map { (it as Map<*, *>)["id"] }))
        repository.finishApply(repository.applyDraft())
        return Fixture(public, store, repositoryRoot, repository, coordinator)
    }

    private data class Fixture(val public: File, val store: FaultStore, val repositoryRoot: File,
        val repository: GameModRepository, val coordinator: GameModLibraryCoordinator)

    /** One-shot failures wrap only storage; no archive, repository or coordinator behavior is faked. */
    private class FaultStore(private val delegate: GameModLibraryStore) : GameModLibraryStore by delegate {
        var failRead: String? = null
        var failList: String? = null
        var failWrite: ((String) -> Boolean)? = null
        var failRename = false
        var renameUnsupported = false
        var protectFailedWriteRoot = false
        var stripMarkerOnRefusedRootDelete = false
        var refuseDeleteChildren = false
        val refuseDeleteRoots = mutableSetOf<String>()
        var deliveredBeforeFailure = 0
            private set

        override fun list(relative: String): List<GameModLibraryEntry> {
            if (relative == failList) {
                failList = null
                throw IOException("Injected directory listing failure")
            }
            return delegate.list(relative)
        }

        override fun openRead(relative: String): InputStream {
            val input = delegate.openRead(relative)
            if (relative != failRead) return input
            failRead = null
            return object : FilterInputStream(input) {
                private var delivered = 0
                override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                    if (length == 0) return 0
                    if (delivered >= 11) {
                        deliveredBeforeFailure = delivered
                        throw IOException("Injected stream failure after $delivered bytes")
                    }
                    return `in`.read(buffer, offset, minOf(length, 11 - delivered)).also { if (it > 0) delivered += it }
                }
                override fun read(): Int = ByteArray(1).let { buffer ->
                    if (read(buffer, 0, 1) < 0) -1 else buffer[0].toInt() and 255
                }
            }
        }

        override fun openWrite(relative: String): OutputStream {
            if (failWrite?.invoke(relative) == true) {
                failWrite = null
                if (protectFailedWriteRoot) refuseDeleteRoots.add(relative.substringBefore('/'))
                throw IOException("Injected openWrite failure")
            }
            return delegate.openWrite(relative)
        }

        override fun delete(relative: String): Boolean {
            if (relative in refuseDeleteRoots) {
                // A recursive provider can remove metadata before hitting an undeletable PNG.
                if (stripMarkerOnRefusedRootDelete) delegate.delete("$relative/.yahagi-package.json")
                return false
            }
            if (refuseDeleteChildren && refuseDeleteRoots.any {
                relative.startsWith("$it/") && relative != "$it/.yahagi-package.json"
            }) return false
            return delegate.delete(relative)
        }

        override fun rename(from: String, to: String): Boolean {
            if (failRename) {
                failRename = false
                throw IOException("Injected rename failure")
            }
            return if (renameUnsupported) false else delegate.rename(from, to)
        }
    }

    private fun commitFreshScan(fixture: Fixture) {
        val scan = fixture.coordinator.scan()
        assertTrue("Recovered sources must be readable", entries(scan).none { it["kind"] in listOf("invalid", "missing") })
        fixture.coordinator.commitScan(token(scan))
    }

    private fun token(scan: Map<String, Any?>) = scan["token"] as String
    @Suppress("UNCHECKED_CAST")
    private fun entries(scan: Map<String, Any?>) = scan["entries"] as List<Map<String, Any?>>
    @Suppress("UNCHECKED_CAST")
    private fun packages(repository: GameModRepository) = repository.status()["packages"] as List<Map<String, Any?>>
    private fun repositoryState(repository: GameModRepository) = gson.toJson(repository.status())
    private fun read(repository: GameModRepository) = repository.openResource(
        "https://w01x.kancolle-server.com/$resource?version=1", "GET", emptyMap())!!.inputStream.use { it.readBytes() }
    private fun files(root: File): Map<String, String> = root.walkTopDown().filter { it.isFile }.associate {
        it.relativeTo(root).invariantSeparatorsPath to MessageDigest.getInstance("SHA-256").digest(it.readBytes())
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 255) }
    }
    // Confirming other unchanged candidates may rotate the two valid library-index slots.
    // Every ZIP, editable byte and package marker must still be preserved across this fault.
    private fun sourceFiles(root: File) = files(root).filterKeys { it !in setOf("library.json", ".yahagi-library-backup.json") }
    private fun assertCode(code: String, action: () -> Unit) {
        val error = runCatching(action).exceptionOrNull()
        assertTrue("Expected $code, got $error", error is GameModException)
        assertEquals(code, (error as GameModException).code)
    }

    private fun zip(files: Map<String, ByteArray>): ByteArray = ByteArrayOutputStream().also { output ->
        ZipOutputStream(output).use { zip -> files.forEach { (path, bytes) ->
            zip.putNextEntry(ZipEntry(path)); zip.write(bytes); zip.closeEntry()
        } }
    }.toByteArray()

    private fun png(red: Int): ByteArray = ByteArrayOutputStream().also { output ->
        val data = DataOutputStream(output)
        data.write(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
        fun chunk(type: String, bytes: ByteArray) {
            val tag = type.toByteArray(Charsets.US_ASCII)
            data.writeInt(bytes.size); data.write(tag); data.write(bytes)
            data.writeInt(CRC32().apply { update(tag); update(bytes) }.value.toInt())
        }
        chunk("IHDR", ByteArrayOutputStream().also { DataOutputStream(it).apply {
            writeInt(1); writeInt(1); write(byteArrayOf(8, 6, 0, 0, 0))
        } }.toByteArray())
        chunk("IDAT", ByteArrayOutputStream().also { DeflaterOutputStream(it).use {
            it.write(byteArrayOf(0, red.toByte(), 0, 0, -1))
        } }.toByteArray())
        chunk("IEND", byteArrayOf())
    }.toByteArray()
}
