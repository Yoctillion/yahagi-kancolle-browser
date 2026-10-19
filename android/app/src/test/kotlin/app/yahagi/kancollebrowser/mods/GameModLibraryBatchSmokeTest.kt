package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FilterInputStream
import java.io.InputStream
import java.util.UUID
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Local JVM smoke: real ZIP parsing, PNG decoding, source IO and immutable repository imports. */
class GameModLibraryBatchSmokeTest {
    @get:Rule val temporary = TemporaryFolder()
    private val path = "kcs2/resources/ship/full/0001_1234.png"

    @Test fun `repeat scan reuses only a full-content validation performed by this library instance`() {
        val public = temporary.newFolder()
        public.resolve("ship/$path").apply { parentFile!!.mkdirs(); writeBytes(png(1)) }
        val workspace = temporary.newFolder()
        val store = CountingStore(GameModFileLibraryStore(public))
        val library = GameModLibrary(store, workspace)
        val first = library.scan()
        assertEquals("new", first.items.single()["status"])
        assertEquals(1, validationCount(workspace))
        library.acceptScan(first.token)
        library.discardScan(first.token)
        store.reset()
        val repeat = library.scan()
        assertEquals("unchanged", repeat.items.single()["status"])
        assertEquals("A matching full SHA must avoid a second archive/PNG validation", 0, validationCount(workspace))
        assertEquals("Both source passes remain mandatory", 2, store.resourceReads)
        assertTrue(library.acceptScan(repeat.token).single().archive.isFile)
        library.discardScan(repeat.token)

        // Process restart deliberately loses this optimization: public metadata is not proof of validation.
        val restartedWorkspace = temporary.newFolder()
        val restarted = GameModLibrary(store, restartedWorkspace)
        assertEquals("unchanged", restarted.scan().items.single()["status"])
        assertEquals(1, validationCount(restartedWorkspace))
    }

    @Test fun `large single source file advances bytes before either read pass completes`() {
        val public = temporary.newFolder()
        val bytes = png(1, 128 * 1024)
        public.resolve("ship/$path").apply { parentFile!!.mkdirs(); writeBytes(bytes) }
        val progress = GameModProgress()
        progress.begin("scan")
        val observedPasses = mutableSetOf<Int>()
        var sourceReads = 0
        val delegate = GameModFileLibraryStore(public)
        val store = object : GameModLibraryStore by delegate {
            override fun openRead(relative: String): InputStream {
                val input = delegate.openRead(relative)
                if (!relative.endsWith(".png")) return input
                val pass = ++sourceReads
                return object : FilterInputStream(input) {
                    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                        val snapshot = progress.snapshot()!!
                        val completed = snapshot["completedBytes"] as Long
                        if (snapshot["phase"] == "read" && snapshot["completedFiles"] == 0 && completed in 1 until bytes.size.toLong()) {
                            observedPasses.add(pass)
                        }
                        return `in`.read(buffer, offset, length)
                    }
                }
            }
        }
        val library = GameModLibrary(store, temporary.newFolder(), progress)
        assertEquals("new", library.scan().items.single()["status"])
        assertEquals("Copy and confirmation hash must both report in-file bytes", setOf(1, 2), observedPasses)
    }

    @Test fun `single ZIP import duplicate and saved identity reuse all finish one real package`() {
        val progress = GameModProgress()
        val public = temporary.newFolder()
        val library = GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder(), progress)
        val repository = GameModRepository(temporary.newFolder(), progress)
        val coordinator = GameModLibraryCoordinator(repository, library, temporary.newFolder(), progress)
        fun imported(repo: GameModRepository, connection: GameModLibraryCoordinator): Map<String, Any?> {
            progress.begin("import")
            val preview = repo.preflight(zip(png(1)).inputStream(), "ship.zip")
            val result = connection.commitImport(preview["token"] as String)
            val snapshot = progress.snapshot()!!
            assertEquals(1, snapshot["totalPackages"])
            assertEquals(1, snapshot["completedPackages"])
            assertEquals("ship", snapshot["currentPackage"])
            return result
        }
        val first = imported(repository, coordinator)
        assertEquals(true, imported(repository, coordinator)["duplicate"])
        val fresh = GameModRepository(temporary.newFolder(), progress)
        val reinstalled = GameModLibraryCoordinator(fresh, library, temporary.newFolder(), progress)
        assertEquals(first["id"], imported(fresh, reinstalled)["id"])
    }

    @Test fun `sixty ZIP imports and directory rescans survive mixed edits corruption and confirmation races`() {
        val public = temporary.newFolder()
        repeat(60) { index -> public.resolve("archive-$index.zip").writeBytes(zip(png(index + 1))) }
        val store = CountingStore(GameModFileLibraryStore(public))
        val workspace = temporary.newFolder()
        val repository = GameModRepository(temporary.newFolder())
        val library = GameModLibrary(store, workspace)
        val coordinator = GameModLibraryCoordinator(repository, library, temporary.newFolder())
        var started = System.nanoTime()
        val first = coordinator.scan()
        val firstMs = elapsed(started)
        assertEquals(60, entries(first).count { it["kind"] == "new" })
        val initialValidations = validationCount(workspace)
        assertEquals(60, initialValidations)
        started = System.nanoTime()
        coordinator.commitScan(first["token"] as String)
        val importMs = elapsed(started)
        assertEquals(60, packages(repository).size)
        assertEquals(0, public.listFiles()!!.count { it.extension == "zip" })
        assertEquals(60, public.listFiles()!!.count { it.isDirectory })
        assertEquals(emptyList<String>(), (repository.status()["draft"] as Map<*, *>)["enabledPackages"])

        store.reset()
        started = System.nanoTime()
        val repeated = coordinator.scan()
        val repeatMs = elapsed(started)
        assertEquals(60, entries(repeated).count { it["kind"] == "unchanged" })
        val repeatValidations = validationCount(workspace)
        assertEquals(0, repeatValidations)
        assertEquals("Repeat inspection still reads all source bytes twice", 120, store.resourceReads)
        val repeatBytes = store.resourceBytes
        coordinator.commitScan(repeated["token"] as String)
        assertEquals(60, packages(repository).size)

        val images = public.walkTopDown().filter { it.isFile && it.name == "0001_1234.png" }.sortedBy { it.path }.toList()
        images.take(5).forEachIndexed { index, file ->
            val modified = file.lastModified()
            file.writeBytes(png(index + 101))
            file.setLastModified(modified)
        }
        images.drop(5).take(2).forEach { it.writeBytes(byteArrayOf(1, 2, 3)) }
        started = System.nanoTime()
        val mixed = coordinator.scan()
        val mixedMs = elapsed(started)
        assertEquals(5, entries(mixed).count { it["kind"] == "updated" })
        assertEquals(2, entries(mixed).count { it["kind"] == "invalid" })
        assertEquals(53, entries(mixed).count { it["kind"] == "unchanged" })
        val oldInvalid = packages(repository).filter { pack -> images.drop(5).take(2).any { image ->
            entries(mixed).any { it["id"] == pack["id"] && it["path"] == image.relativeTo(public).invariantSeparatorsPath.substringBefore('/') }
        } }.associateBy { it["id"] }
        coordinator.commitScan(mixed["token"] as String)
        assertEquals(60, packages(repository).size)
        assertTrue(oldInvalid.isNotEmpty())
        oldInvalid.forEach { (id, previous) -> assertEquals(previous, packages(repository).single { it["id"] == id }) }

        val pending = coordinator.scan()
        val before = packages(repository)
        images.last().writeBytes(png(200))
        val error = runCatching { coordinator.commitScan(pending["token"] as String) }.exceptionOrNull()
        assertEquals("library_changed", (error as? GameModException)?.code)
        assertEquals(before, packages(repository))
        println("MOD_BATCH_SMOKE packages=60 firstScanMs=$firstMs importMs=$importMs repeatScanMs=$repeatMs mixedScanMs=$mixedMs initialArchiveValidations=$initialValidations repeatArchiveValidations=$repeatValidations repeatSourceReads=120 repeatSourceBytes=$repeatBytes")
    }

    @Test fun `import cleans only the changed package and preserves another applied leased revision`() {
        val root = temporary.newFolder()
        val repository = GameModRepository(root)
        val a = UUID.randomUUID().toString()
        val b = UUID.randomUUID().toString()
        fun import(id: String, value: Int) {
            val preview = repository.preflightLibrary(zip(png(value)).inputStream(), "ship.zip")
            repository.commitLibraryImport(preview["token"] as String, id, value.toString())
        }
        import(a, 1); import(b, 2)
        val aResources = ((packages(repository).single { it["id"] == a }["resources"] as List<*>))
            .map { (it as Map<*, *>)["id"] as String }
        val config = mapOf("master" to true, "order" to listOf(a, b), "enabledPackages" to listOf(a), "enabledResources" to aResources)
        repository.saveDraft(config); repository.finishApply(repository.applyDraft())
        val oldA = root.resolve("packages/$a/revisions").listFiles()!!.single()
        val appliedB = root.resolve("packages/$b/revisions").listFiles()!!.single()
        val unrelated = root.resolve("packages/$a/revisions/unreferenced-checkpoint/file.txt")
        val stream = repository.openResource("https://w01x.kancolle-server.com/$path", "GET", emptyMap())!!.inputStream
        try {
            import(a, 3)
            // Disabled packages are still part of the applied inventory. Create an
            // additional draft-only revision to exercise immediate obsolete cleanup.
            import(b, 5)
            val oldB = root.resolve("packages/$b/revisions").listFiles()!!.single { it != appliedB }
            // An unrelated private orphan is discovered by startup/apply maintenance,
            // not by every package in the batch. This also detects accidental global scans.
            unrelated.apply { parentFile!!.mkdirs(); writeText("retained until discovery") }
            import(b, 4)
            assertFalse("The updated package's obsolete draft revision must be reclaimed", oldB.exists())
            assertTrue("Disabled applied package revisions remain available for cancel", appliedB.exists())
            assertTrue("An unrelated package must not be rediscovered during this import", unrelated.exists())
            assertTrue("Applied old revisions survive another package's import", oldA.exists())
            repository.saveDraft(config); repository.finishApply(repository.applyDraft())
            assertTrue("The package lease also defers orphan cleanup discovered by apply", unrelated.exists())
            assertTrue("An open old stream keeps its immutable revision", oldA.exists())
            assertArrayEquals(png(1), stream.readBytes())
        } finally { stream.close() }
        assertFalse("The final lease release reclaims the old applied revision", oldA.exists())
        assertFalse("Apply's discovery queues the unrelated orphan for the final lease release", unrelated.exists())
    }

    private fun validationCount(workspace: File) = workspace.walkTopDown().count { it.isDirectory && it.name == "validate" }
    private fun entries(scan: Map<String, Any?>) = (scan["entries"] as List<*>).filterIsInstance<Map<*, *>>()
    private fun packages(repository: GameModRepository) = (repository.status()["packages"] as List<*>).filterIsInstance<Map<*, *>>()
    private fun elapsed(started: Long) = (System.nanoTime() - started) / 1_000_000
    private fun zip(bytes: ByteArray) = ByteArrayOutputStream().also { output ->
        ZipOutputStream(output).use { zip -> zip.putNextEntry(ZipEntry(path)); zip.write(bytes); zip.closeEntry() }
    }.toByteArray()

    private class CountingStore(private val delegate: GameModLibraryStore) : GameModLibraryStore by delegate {
        var resourceReads = 0
        var resourceBytes = 0L
        fun reset() { resourceReads = 0; resourceBytes = 0 }
        override fun openRead(relative: String): InputStream {
            val input = delegate.openRead(relative)
            if (!relative.endsWith(".png")) return input
            resourceReads++
            return object : FilterInputStream(input) {
                override fun read(): Int = `in`.read().also { if (it >= 0) resourceBytes++ }
                override fun read(bytes: ByteArray, offset: Int, length: Int): Int =
                    `in`.read(bytes, offset, length).also { if (it > 0) resourceBytes += it }
            }
        }
    }

    private fun png(value: Int, paddingBytes: Int = 0): ByteArray = ByteArrayOutputStream().also { output ->
        val data = DataOutputStream(output)
        data.write(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
        fun chunk(name: String, bytes: ByteArray) {
            val tag = name.toByteArray()
            data.writeInt(bytes.size); data.write(tag); data.write(bytes)
            data.writeInt(CRC32().also { it.update(tag); it.update(bytes) }.value.toInt())
        }
        chunk("IHDR", ByteArrayOutputStream().also { DataOutputStream(it).apply { writeInt(1); writeInt(1); write(byteArrayOf(8, 6, 0, 0, 0)) } }.toByteArray())
        if (paddingBytes > 0) chunk("tEXt", ByteArray(paddingBytes))
        chunk("IDAT", ByteArrayOutputStream().also { DeflaterOutputStream(it).use { it.write(byteArrayOf(0, value.toByte(), 0, 0, -1)) } }.toByteArray())
        chunk("IEND", byteArrayOf())
    }.toByteArray()
}
