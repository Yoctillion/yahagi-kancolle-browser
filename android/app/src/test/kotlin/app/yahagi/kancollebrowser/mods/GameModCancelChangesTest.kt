package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class GameModCancelChangesTest {
    @get:Rule val temporary = TemporaryFolder()
    private val target = "kcs2/resources/ship/full/0001_abcd.png"
    private val url = "https://w01x.kancolle-server.com/$target?version=1"

    @Test fun `cancel restores applied switches resource choices priority and staged deletion without changing session`() {
        val root = temporary.newFolder()
        val repo = GameModRepository(root)
        import(repo); import(repo)
        val ids = packageIds(repo)
        val resources = resourceIds(repo)
        repo.saveDraft(config(ids.reversed(), ids, resources))
        apply(repo)
        repo.openResource(url, "GET", emptyMap())!!.inputStream.use { it.readBytes() }
        val before = repo.status()
        val portraits = repo.portraitSnapshot()
        val files = root.resolve("packages").walkTopDown().filter { it.isFile }.associate { it.relativeTo(root).path to it.readBytes().toList() }
        repo.saveDraft(config(ids, ids.take(1), resources.take(1), master = false))
        repo.removePackage(ids.first())
        assertEquals(true, repo.status()["pending"])

        cancel(repo)

        assertEquals(before, repo.status())
        assertEquals(portraits, repo.portraitSnapshot())
        assertEquals(files, root.resolve("packages").walkTopDown().filter { it.isFile }.associate { it.relativeTo(root).path to it.readBytes().toList() })
        assertEquals(before["draft"], GameModRepository(root).status()["draft"])
        assertEquals(false, GameModRepository(root).status()["pending"])
    }

    @Test fun `cancel reset repeatedly keeps all packages and existing request streams usable`() {
        val root = temporary.newFolder()
        val repo = GameModRepository(root)
        import(repo); import(repo)
        repo.saveDraft(config(packageIds(repo), packageIds(repo), resourceIds(repo)))
        apply(repo)
        val before = repo.status()
        val token = repo.portraitSnapshot()["token"]
        repeat(3) {
            val response = repo.openResource(url, "GET", emptyMap())!!
            repo.resetAll()
            assertTrue(packages(repo).all { it["pendingRemoval"] == true })
            cancel(repo)
            assertEquals(before["draft"], repo.status()["draft"])
            assertEquals(before["applied"], repo.status()["applied"])
            assertEquals(before["sessionId"], repo.status()["sessionId"])
            assertEquals(token, repo.portraitSnapshot()["token"])
            assertEquals(false, repo.status()["pending"])
            assertArrayEquals(png(), response.inputStream.use { it.readBytes() })
            assertEquals(2, packages(repo).size)
            assertFalse(packages(repo).any { it["pendingRemoval"] == true })
        }
        val restored = GameModRepository(root)
        assertEquals(false, restored.status()["pending"])
        assertNotNull(restored.openResource(url, "GET", emptyMap()).also { it?.inputStream?.close() })
    }

    @Test fun `cancel retains newly imported package disabled at end without changing applied configuration`() {
        val root = temporary.newFolder()
        val repo = GameModRepository(root)
        import(repo); import(repo)
        val appliedIds = packageIds(repo).reversed()
        val appliedResources = resourceIds(repo)
        repo.saveDraft(config(appliedIds, appliedIds, appliedResources))
        apply(repo)
        val before = repo.status()
        val portraits = repo.portraitSnapshot()
        import(repo)
        val newId = packageIds(repo).last()
        repo.saveDraft(config(packageIds(repo), packageIds(repo), resourceIds(repo)))
        repo.removePackage(newId)
        repo.removePackage(appliedIds.first())

        cancel(repo)

        val draft = repo.status()["draft"] as Map<*, *>
        assertEquals(appliedIds + newId, draft["order"])
        assertEquals(appliedIds, draft["enabledPackages"])
        assertEquals(appliedResources, draft["enabledResources"])
        assertEquals(before["applied"], repo.status()["applied"])
        assertEquals(before["sessionId"], repo.status()["sessionId"])
        assertEquals(portraits, repo.portraitSnapshot())
        assertEquals(false, repo.status()["pending"])
        assertEquals(3, packages(repo).size)
        assertFalse(packages(repo).any { it["pendingRemoval"] == true })
        assertTrue(root.resolve("packages/$newId").isDirectory)
        val restored = GameModRepository(root)
        assertEquals(draft, restored.status()["draft"])
        assertEquals(before["applied"], restored.status()["applied"])
        assertEquals(false, restored.status()["pending"])
    }

    @Test fun `cancel before first apply keeps import available and has no pending changes`() {
        val root = temporary.newFolder()
        val repo = GameModRepository(root)
        val applied = repo.status()["applied"]
        import(repo)
        val id = packageIds(repo).single()
        assertEquals(true, repo.status()["pending"])

        cancel(repo)

        assertEquals(config(listOf(id), emptyList(), emptyList(), master = false), repo.status()["draft"])
        assertEquals(applied, repo.status()["applied"])
        assertEquals(false, repo.status()["pending"])
        assertTrue(root.resolve("packages/$id").isDirectory)
        assertEquals(false, GameModRepository(root).status()["pending"])
    }

    @Test fun `repeated cancel is idempotent and does not reset completed hits`() {
        val root = temporary.newFolder()
        val repo = GameModRepository(root)
        import(repo)
        repo.saveDraft(config(packageIds(repo), packageIds(repo), resourceIds(repo)))
        apply(repo)
        repo.openResource(url, "GET", emptyMap())!!.inputStream.use { it.readBytes() }
        val before = repo.status()
        val index = root.resolve("state.json").readText()
        repeat(3) { cancel(repo) }
        assertEquals(before, repo.status())
        assertEquals(index, root.resolve("state.json").readText())
    }

    @Test fun `cancel is rejected during prepared apply and leaves pending state unchanged`() {
        val root = temporary.newFolder()
        val repo = GameModRepository(root)
        import(repo)
        repo.removePackage(packageIds(repo).single())
        val before = repo.status()
        val index = root.resolve("state.json").readText()
        val token = repo.prepareApply()
        try {
            try { cancel(repo); fail("cancel must not race prepared apply") }
            catch (error: GameModException) { assertEquals("busy", error.code) }
            assertEquals(before, repo.status())
            assertEquals(index, root.resolve("state.json").readText())
        } finally { repo.cancelPreparedApply(token) }
        cancel(repo)
        assertEquals(false, repo.status()["pending"])
    }

    @Test fun `failed cancel persistence keeps in memory state session and deletion flags unchanged`() {
        val root = temporary.newFolder()
        val repo = GameModRepository(root)
        import(repo)
        repo.saveDraft(config(packageIds(repo), packageIds(repo), resourceIds(repo)))
        apply(repo)
        repo.removePackage(packageIds(repo).single())
        val before = repo.status()
        val portraits = repo.portraitSnapshot()
        val index = root.resolve("state.json")
        val durable = index.readText()
        assertTrue(index.delete()); assertTrue(index.mkdir())
        try {
            try { cancel(repo); fail("cancel must report persistence failure") }
            catch (error: GameModException) { assertEquals("storage_error", error.code) }
            assertEquals(before, repo.status())
            assertEquals(portraits, repo.portraitSnapshot())
            assertTrue(packages(repo).single()["pendingRemoval"] as Boolean)
            assertFalse(root.listFiles()!!.any { it.name.startsWith("state-") && it.name.endsWith(".tmp") })
        } finally {
            assertTrue(index.delete())
            index.writeText(durable)
        }
        assertEquals(true, GameModRepository(root).status()["pending"])
        cancel(repo)
        assertEquals(false, repo.status()["pending"])
    }

    @Test fun `three real packages survive three cancellation rounds for each package with active bytes and counters unchanged`() {
        val fixturePaths = listOf("YAHAGI_REAL_MOD_ZIP", "YAHAGI_REAL_VOICE_MOD_ZIP", "YAHAGI_REAL_FUBUKI_MOD_ZIP")
            .map { System.getenv(it)?.takeIf(String::isNotBlank) }
        assumeTrue("Set all three real-mod ZIP fixture environment variables for the optional cancellation regression", fixturePaths.all { it != null })
        val fixtures = fixturePaths.map { File(it!!) }
        fixtures.forEach { assertTrue("Missing fixture: ${it.path}", it.isFile) }
        val sourceHashes = fixtures.associateWith(::hash)
        val root = temporary.newFolder("real-package-cancellation")
        val officialMarker = temporary.newFile("official-cache-marker").apply { writeText("keep official cache") }
        val markerHash = hash(officialMarker)
        val repo = GameModRepository(root)
        try {
            fixtures.forEach { file ->
                val preview = file.inputStream().use { repo.preflight(it, file.name) }
                repo.commitImport(preview["token"] as String)
            }
            val ids = packageIds(repo)
            assertEquals(3, ids.size)
            val supported = packages(repo).flatMap { it["resources"] as List<*> }
                .map { it as Map<*, *> }.filter { it["supported"] == true }
            val selectedIds = supported.map { it["id"] as String }
            repo.saveDraft(config(ids, ids, selectedIds))
            apply(repo)
            val activePaths = (repo.status()["activeWinners"] as Map<*, *>).keys.filterIsInstance<String>()
            val imagePath = activePaths.first { it.startsWith("kcs2/") && it.endsWith(".png") }
            repo.openResource(realUrl(imagePath), "GET", emptyMap())!!.inputStream.use { assertTrue(it.readBytes().isNotEmpty()) }
            val audioPath = activePaths.first { it.startsWith("kcs/sound/") }
            repo.openResource(realUrl(audioPath), "GET", mapOf("Range" to "bytes=0-31"))!!.inputStream.use { assertEquals(32, it.readBytes().size) }
            val before = repo.status()
            assertTrue((before["hits"] as List<*>).isNotEmpty())
            assertTrue((before["partialHits"] as List<*>).isNotEmpty())
            val portraits = repo.portraitSnapshot()
            val coordinates = repo.activeCoordinateSnapshot()
            val expectedPackageHashes = packageHashes(root)
            val durableHash = hash(root.resolve("state.json"))

            repeat(3) { round ->
                ids.forEachIndexed { index, removedId ->
                    val order = if (round % 2 == 0) ids.reversed() else ids.drop(1) + ids.first()
                    val partialResources = selectedIds.filterIndexed { resourceIndex, _ -> resourceIndex % 3 != index }
                    repo.saveDraft(config(order, ids.filterNot { it == removedId }, partialResources, master = round != 1))
                    repo.removePackage(removedId)
                    assertEquals(true, repo.status()["pending"])
                    assertTrue(packages(repo).single { it["id"] == removedId }["pendingRemoval"] as Boolean)
                    assertEquals(portraits, repo.portraitSnapshot())
                    assertEquals(coordinates, repo.activeCoordinateSnapshot())

                    repo.cancelChanges()

                    assertEquals("round $round package $removedId", before, repo.status())
                    assertEquals(portraits, repo.portraitSnapshot())
                    assertEquals(coordinates, repo.activeCoordinateSnapshot())
                    assertEquals(expectedPackageHashes, packageHashes(root))
                    assertEquals(durableHash, hash(root.resolve("state.json")))
                    assertEquals(markerHash, hash(officialMarker))
                }
            }

            val restored = GameModRepository(root)
            val restoredStatus = restored.status()
            listOf("packages", "draft", "applied", "sessionId", "winners", "activeWinners", "pending").forEach { key ->
                assertEquals("durable $key", before[key], restoredStatus[key])
            }
            assertEquals(portraits["resources"], restored.portraitSnapshot()["resources"])
            assertEquals(expectedPackageHashes, packageHashes(root))
            assertEquals(markerHash, hash(officialMarker))
        } finally {
            sourceHashes.forEach { (file, expected) -> assertEquals(file.path, expected, hash(file)) }
        }
    }

    private fun cancel(repo: GameModRepository) = repo.cancelChanges()
    private fun realUrl(path: String) = "https://w01x.kancolle-server.com/$path?version=1"
    private fun hash(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
    private fun packageHashes(root: File) = root.resolve("packages").walkTopDown().filter { it.isFile }
        .associate { it.relativeTo(root).invariantSeparatorsPath to hash(it) }
    private fun import(repo: GameModRepository) {
        val preview = repo.preflight(zip(), "cache.zip")
        repo.commitImport(preview["token"] as String)
    }
    private fun apply(repo: GameModRepository) { repo.finishApply(repo.applyDraft()) }
    @Suppress("UNCHECKED_CAST") private fun packages(repo: GameModRepository) = repo.status()["packages"] as List<Map<String, Any?>>
    private fun packageIds(repo: GameModRepository) = packages(repo).map { it["id"] as String }
    private fun resourceIds(repo: GameModRepository) = packages(repo).flatMap { it["resources"] as List<*> }.map { (it as Map<*, *>)["id"] as String }
    private fun config(order: List<String>, enabledPackages: List<String>, enabledResources: List<String>, master: Boolean = true) =
        mapOf("master" to master, "order" to order, "enabledPackages" to enabledPackages, "enabledResources" to enabledResources)
    private fun png(): ByteArray = ByteArrayOutputStream().also { out ->
        val data = DataOutputStream(out)
        data.write(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
        fun chunk(type: String, bytes: ByteArray) {
            val kind = type.toByteArray(Charsets.US_ASCII)
            data.writeInt(bytes.size); data.write(kind); data.write(bytes)
            data.writeInt(CRC32().apply { update(kind); update(bytes) }.value.toInt())
        }
        val header = ByteArrayOutputStream().also { DataOutputStream(it).apply { writeInt(1); writeInt(1); write(byteArrayOf(8, 6, 0, 0, 0)) } }.toByteArray()
        val compressed = ByteArrayOutputStream().also { DeflaterOutputStream(it).use { it.write(byteArrayOf(0, 0, 0, 0, -1)) } }.toByteArray()
        chunk("IHDR", header); chunk("IDAT", compressed); chunk("IEND", byteArrayOf())
    }.toByteArray()
    private fun zip() = ByteArrayOutputStream().also { out ->
        ZipOutputStream(out).use { it.putNextEntry(ZipEntry("cache/$target")); it.write(png()); it.closeEntry() }
    }.toByteArray().inputStream()
}
