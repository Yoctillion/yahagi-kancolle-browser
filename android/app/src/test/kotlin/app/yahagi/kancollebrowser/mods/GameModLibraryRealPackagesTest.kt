package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.Random
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream

/** Read-only real archives, caller-owned public folders, and disposable private repositories. */
@RunWith(Parameterized::class)
class GameModLibraryRealPackagesTest(private val round: Int) {
    @get:Rule val temporary = TemporaryFolder()

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "real library round {0}")
        fun rounds(): List<Array<Any>> = (1..3).map { arrayOf<Any>(it) }
    }

    @Test fun `three real packs migrate edit scan cancel rollback and reinstall without losing applied choices`() {
        val paths = listOf("YAHAGI_REAL_MOD_ZIP", "YAHAGI_REAL_VOICE_MOD_ZIP", "YAHAGI_REAL_FUBUKI_MOD_ZIP")
            .map { System.getenv(it)?.takeIf(String::isNotBlank) }
        assumeTrue("Set all three real-mod ZIP fixture environment variables", paths.all { it != null })
        val fixtures = paths.map { File(it!!) }
        fixtures.forEach { assertTrue("Configured fixture does not exist: $it", it.isFile) }
        val hashes = fixtures.map(::hash)
        try {
            val publicRoot = temporary.newFolder("public-library")
            val store = GameModFileLibraryStore(publicRoot)
            var library = GameModLibrary(store, temporary.newFolder("library-worker"))
            val originalRoot = temporary.newFolder("original-install")
            val original = GameModRepository(originalRoot)
            fixtures.forEach { file ->
                val preview = file.inputStream().use { original.preflight(it, file.name) }
                original.commitImport(preview["token"] as String)
            }
            val originalPackages = packages(original)
            val ids = originalPackages.map { it["id"] as String }
            val changedPaths = originalPackages.associate { entry -> entry["id"] as String to images(entry).first()["path"] as String }
            val removedPaths = originalPackages.associate { entry -> entry["id"] as String to images(entry)[1]["path"] as String }
            val order = ids.drop(round % 3) + ids.take(round % 3)
            val selected = originalPackages.flatMap { entry -> resources(entry).filter { it["supported"] == true && it["path"] != removedPaths[entry["id"]] }.map { it["id"] as String } }
            original.saveDraft(mapOf("master" to true, "order" to order, "enabledPackages" to ids, "enabledResources" to selected))
            apply(original)
            val originalConfiguration = configuration(original)
            val originalContent = content(original)
            val originalCoordinates = coordinates(original)
            assertTrue(originalContent.keys.any { it.startsWith("kcs/sound/") })
            assertTrue(originalCoordinates.isNotEmpty())

            val publicDirectories = originalPackages.associate { entry ->
                val id = entry["id"] as String
                val export = temporary.newFolder("export-$id")
                original.exportPackageTree(id, export)
                val saved = library.savePackage(id, entry["name"] as String, export)
                original.attachLibraryFingerprint(id, saved["contentHash"] as String)
                id to publicRoot.resolve(saved["path"] as String)
            }
            library.saveAppliedConfiguration(original.exportAppliedConfiguration())
            assertEquals(originalContent, content(original))
            assertEquals(originalConfiguration, configuration(original))

            // Reinstallation drops every private file and process-local scan token.
            library = GameModLibrary(GameModFileLibraryStore(publicRoot), temporary.newFolder("reinstalled-library-worker"))
            val restoredRoot = temporary.newFolder("reinstalled-app")
            var restored = GameModRepository(restoredRoot)
            val recovered = scanInto(library, restored)
            assertEquals(ids.toSet(), recovered.map { it.id }.toSet())
            restored.restoreLibraryConfiguration(library.appliedConfiguration()!!)
            apply(restored)
            assertEquals(originalConfiguration, configuration(restored))
            assertEquals(originalContent, content(restored))
            assertEquals(originalCoordinates, coordinates(restored))
            val baselinePackages = packages(restored)

            val edits = linkedMapOf<String, ByteArray>()
            val probePaths = linkedMapOf<String, String>()
            publicDirectories.entries.forEachIndexed { index, (id, folder) ->
                val image = folder.resolve(changedPaths.getValue(id))
                val oldSize = image.length(); val oldTime = image.lastModified()
                val edited = paddedPng(oldSize.toInt(), round * 17 + index)
                image.writeBytes(edited)
                assertTrue(image.setLastModified(oldTime))
                assertEquals("Content scanning must not depend on byte length", oldSize, image.length())
                assertEquals("Content scanning must not depend on mtime", oldTime, image.lastModified())
                edits[changedPaths.getValue(id)] = edited
            }
            val imageOnlyScan = library.scan()
            assertEquals("Same-size, same-mtime image changes must independently be detected", 3,
                imageOnlyScan.items.count { it["status"] == "updated" })
            library.discardScan(imageOnlyScan.token)
            publicDirectories.entries.forEachIndexed { index, (id, folder) ->
                assertTrue(folder.resolve(removedPaths.getValue(id)).delete())
                val extra = "kcs2/img/library_probe_${round}_$index.png"
                folder.resolve(extra).apply { parentFile!!.mkdirs(); writeBytes(paddedPng(128, round + index)) }
                probePaths[id] = extra
            }
            val wavePath = "kcs/sound/kclibrarytest/9090.wav"
            val waveTarget = wavePath.removeSuffix(".wav") + ".mp3"
            val waveBytes = wav(round)
            publicDirectories.getValue(ids[1]).resolve(wavePath).apply { parentFile!!.mkdirs(); writeBytes(waveBytes) }

            val firstScan = library.scan()
            assertEquals(3, firstScan.items.count { it["status"] == "updated" })
            acceptInto(library, firstScan, restored)
            assertEquals("Draft edits cannot change the running session", originalContent, content(restored))
            assertEquals(originalCoordinates, coordinates(restored))
            assertEquals(true, restored.status()["pending"])
            restored = GameModRepository(restoredRoot)
            assertEquals("Process death cannot publish an update", originalContent, content(restored))
            restored.cancelChanges()
            assertEquals(baselinePackages, packages(restored))
            assertEquals(originalConfiguration, configuration(restored))
            assertEquals(false, restored.status()["pending"])

            // Public marker hashes already describe the edited files. Private fingerprints
            // deliberately remain old after cancel, so unchanged scan candidates must retry.
            val retried = scanInto(library, restored)
            assertEquals(3, retried.size)
            assertEquals(order, draft(restored)["order"])
            val enabledBefore = (draft(restored)["enabledResources"] as List<*>).toSet()
            packages(restored).forEach { entry ->
                val id = entry["id"] as String
                val prior = resources(baselinePackages.single { it["id"] == id }).associate { it["path"] to it["id"] }
                resources(entry).filter { it["path"] in prior }.forEach { resource -> assertEquals(prior[resource["path"]], resource["id"]) }
                assertFalse(resources(entry).any { it["path"] == removedPaths[id] })
                val probe = resources(entry).single { it["path"] == probePaths[id] }
                assertFalse("New resources are not silently enabled", probe["id"] in enabledBefore)
            }
            val wave = packages(restored).flatMap(::resources).single { it["path"] == waveTarget }
            assertFalse(wave["id"] in enabledBefore)

            val update = restored.applyDraft()
            edits.forEach { (path, bytes) -> assertArrayEquals(bytes, read(restored, path)) }
            probePaths.values.forEach { assertNull(read(restored, it)) }
            assertNull(read(restored, waveTarget))
            restored.rollbackApply(update)
            assertEquals(originalContent, content(restored))
            restored = GameModRepository(restoredRoot)
            assertEquals(originalContent, content(restored))
            apply(restored)
            edits.forEach { (path, bytes) -> assertArrayEquals(bytes, read(restored, path)) }
            assertEquals(originalCoordinates, coordinates(restored))

            val newlySelected = packages(restored).flatMap(::resources).filter { it["path"] in probePaths.values || it["path"] == waveTarget }.map { it["id"] as String }
            restored.saveDraft(draft(restored) + ("enabledResources" to ((draft(restored)["enabledResources"] as List<*>) + newlySelected)))
            apply(restored)
            val waveResponse = restored.openResource(url(waveTarget), "GET", emptyMap())!!
            assertEquals("audio/wav", waveResponse.mimeType)
            assertArrayEquals(waveBytes, waveResponse.inputStream.use { it.readBytes() })
            val finalContent = content(restored)
            val finalConfiguration = configuration(restored)
            library.saveAppliedConfiguration(restored.exportAppliedConfiguration())

            val secondInstall = GameModRepository(temporary.newFolder("second-reinstall"))
            val secondLibrary = GameModLibrary(GameModFileLibraryStore(publicRoot), temporary.newFolder("second-library-worker"))
            scanInto(secondLibrary, secondInstall)
            secondInstall.restoreLibraryConfiguration(secondLibrary.appliedConfiguration()!!)
            apply(secondInstall)
            assertEquals(finalConfiguration, configuration(secondInstall))
            assertEquals(finalContent, content(secondInstall))
            assertEquals(originalCoordinates, coordinates(secondInstall))
            ids.forEach { id ->
                secondInstall.removePackage(id)
                assertTrue(publicDirectories.getValue(id).isDirectory)
                secondInstall.cancelChanges()
                assertEquals(false, secondInstall.status()["pending"])
                assertEquals(finalContent, content(secondInstall))
            }
            // Explicit deletion is durable only after apply, and the library tombstone
            // prevents a later reinstall from treating a leftover folder as a new package.
            secondInstall.removePackage(ids.last()); apply(secondInstall)
            assertEquals(emptyList<String>(), secondLibrary.deletePackages(listOf(ids.last())))
            secondLibrary.saveAppliedConfiguration(secondInstall.exportAppliedConfiguration())
            val deletedScan = secondLibrary.scan()
            assertFalse(deletedScan.items.any { it["id"] == ids.last() })
            secondLibrary.discardScan(deletedScan.token)
            assertEquals(2, packages(secondInstall).size)
        } finally {
            fixtures.zip(hashes).forEach { (file, before) -> assertEquals("Fixture must stay unchanged: ${file.name}", before, hash(file)) }
        }
    }

    private fun scanInto(library: GameModLibrary, repo: GameModRepository): List<GameModLibraryCandidate> = acceptInto(library, library.scan(), repo)
    private fun acceptInto(library: GameModLibrary, scan: GameModLibraryScan, repo: GameModRepository): List<GameModLibraryCandidate> {
        val accepted = library.acceptScan(scan.token)
        val known = packages(repo).associate { it["id"] as String to it["sourceFingerprint"] }
        val changed = accepted.filter { known[it.id] != it.contentHash }
        changed.forEach { item ->
            val preview = item.archive.inputStream().use { repo.preflight(it, "${item.name}.zip") }
            repo.commitLibraryImport(preview["token"] as String, item.id, item.contentHash)
        }
        library.discardScan(scan.token)
        return changed
    }
    @Suppress("UNCHECKED_CAST") private fun packages(repo: GameModRepository) = repo.status()["packages"] as List<Map<String, Any?>>
    @Suppress("UNCHECKED_CAST") private fun resources(entry: Map<String, Any?>) = entry["resources"] as List<Map<String, Any?>>
    private fun images(entry: Map<String, Any?>) = resources(entry).filter { it["supported"] == true && (it["path"] as String).endsWith(".png") }
    @Suppress("UNCHECKED_CAST") private fun draft(repo: GameModRepository) = repo.status()["draft"] as Map<String, Any?>
    private fun apply(repo: GameModRepository) = repo.finishApply(repo.applyDraft())
    private fun read(repo: GameModRepository, path: String) = repo.openResource(url(path), "GET", emptyMap())?.inputStream?.use { it.readBytes() }
    private fun url(path: String) = "https://w01x.kancolle-server.com/$path?version=1"
    private fun configuration(repo: GameModRepository): Map<String, Any?> {
        val saved = repo.exportAppliedConfiguration()
        val enabled = saved["enabledResources"] as Map<*, *>
        return mapOf("master" to saved["master"], "order" to saved["order"],
            "enabledPackages" to (saved["enabledPackages"] as List<*>).toSet(), "enabledResources" to enabled.mapValues { (it.value as List<*>).toSet() })
    }
    private fun content(repo: GameModRepository): Map<String, String> = (repo.status()["activeWinners"] as Map<*, *>).keys
        .filterIsInstance<String>().filter { it.startsWith("kcs/") || it.startsWith("kcs2/") }.associateWith { path ->
            val response = repo.openResource(url(path), "GET", emptyMap()) ?: error("Missing active resource: $path")
            response.mimeType + ":" + digest(response.inputStream.use { it.readBytes() })
        }
    private fun coordinates(repo: GameModRepository): Map<*, *> = (repo.activeCoordinateSnapshot()["ships"] as Map<*, *>).mapValues { (_, value) -> (value as Map<*, *>)["graph"] }
    private fun hash(file: File) = digest(file.readBytes())
    private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }

    /** Preserve both size and timestamp while replacing pixels with a valid independent PNG. */
    private fun paddedPng(size: Int, seed: Int): ByteArray {
        fun build(padding: Int?) = ByteArrayOutputStream().also { output ->
            val data = DataOutputStream(output); data.write(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
            fun chunk(type: String, bytes: ByteArray) { val kind = type.toByteArray(); data.writeInt(bytes.size); data.write(kind); data.write(bytes); data.writeInt(CRC32().apply { update(kind); update(bytes) }.value.toInt()) }
            chunk("IHDR", ByteArrayOutputStream().also { DataOutputStream(it).apply { writeInt(1); writeInt(1); write(byteArrayOf(8, 6, 0, 0, 0)) } }.toByteArray())
            chunk("IDAT", ByteArrayOutputStream().also { DeflaterOutputStream(it).use { it.write(byteArrayOf(0, seed.toByte(), 33, 44, -1)) } }.toByteArray())
            if (padding != null) chunk("yaHg", ByteArray(padding).also { Random(seed.toLong()).nextBytes(it) })
            chunk("IEND", byteArrayOf())
        }.toByteArray()
        val base = build(null)
        assertTrue("Fixture PNG must fit a test ancillary chunk", size >= base.size + 12)
        return build(size - base.size - 12).also { assertEquals(size, it.size); GameModPng.validate(it) }
    }
    private fun wav(sample: Int): ByteArray = ByteArrayOutputStream().also { output ->
        val data = DataOutputStream(output)
        fun little(value: Int, bytes: Int) { repeat(bytes) { data.writeByte(value ushr (8 * it)) } }
        data.writeBytes("RIFF"); little(38, 4); data.writeBytes("WAVEfmt "); little(16, 4)
        little(1, 2); little(1, 2); little(8000, 4); little(16000, 4); little(2, 2); little(16, 2)
        data.writeBytes("data"); little(2, 4); little(sample, 2)
    }.toByteArray()
}
