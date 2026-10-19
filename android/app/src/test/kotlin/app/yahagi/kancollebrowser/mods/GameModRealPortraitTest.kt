package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Real archives stay read-only; destructive lifecycle tests use isolated repository roots. */
@RunWith(Parameterized::class)
class GameModRealPortraitTest(private val round: Int) {
    @get:Rule val temporary = TemporaryFolder()
    companion object {
        @JvmStatic @Parameterized.Parameters(name = "portrait round {0}")
        fun rounds(): List<Array<Any>> = (1..3).map { arrayOf<Any>(it) }
    }

    @Test fun `three packages read exact stored pngs and repeat switching priority deletion reset and rollback`() {
        val fixturePaths = listOf("YAHAGI_REAL_MOD_ZIP", "YAHAGI_REAL_VOICE_MOD_ZIP", "YAHAGI_REAL_FUBUKI_MOD_ZIP")
            .map { System.getenv(it)?.takeIf(String::isNotBlank) }
        assumeTrue("Set the three real-mod ZIP fixture environment variables", fixturePaths.all { it != null })
        val fixtures = fixturePaths.map { File(it!!) }
        val hashes = fixtures.map(::hash)
        val root = temporary.newFolder("three-real-packs-$round")
        val repo = GameModRepository(root)
        try {
            fixtures.forEach { file ->
                val preview = file.inputStream().use { repo.preflight(it, file.name) }
                repo.commitImport(preview["token"] as String)
            }
            val ids = packageIds(repo)
            val resources = resourceIds(repo)
            repo.saveDraft(config(repo)); apply(repo)
            val all = snapshot(repo)
            assertTrue(images(all).any { (it["path"] as String).contains("/full/") })
            assertTrue(images(all).any { (it["path"] as String).contains("/banner/") })
            val beforeReads = repo.status()
            assertExactStoredBytes(repo, root, all)
            assertEquals(beforeReads, repo.status())
            repeat(2) {
                listOf(mapOf("master" to false), mapOf("enabledPackages" to ids.drop(1)),
                    mapOf("enabledResources" to resources.drop(1))).forEach { change ->
                    val previous = snapshot(repo)
                    repo.saveDraft(config(repo) + change); assertEquals(previous, snapshot(repo))
                    apply(repo); assertExactStoredBytes(repo, root, snapshot(repo))
                    repo.saveDraft(config(repo)); apply(repo); assertExactStoredBytes(repo, root, snapshot(repo))
                }
            }
            // Import a second copy of the actual Fubuki ZIP to exercise real conflicting paths.
            val duplicate = fixtures.last().inputStream().use { repo.preflight(it, "Fubuki duplicate.zip") }
            repo.commitImport(duplicate["token"] as String)
            val duplicateId = packageIds(repo).last()
            repo.saveDraft(config(repo)); apply(repo)
            assertTrue(images(snapshot(repo)).none { (it["id"] as String).startsWith("$duplicateId:") })
            val reverse = packageIds(repo).reversed()
            repo.saveDraft(config(repo) + ("order" to reverse)); apply(repo)
            assertTrue(images(snapshot(repo)).any { (it["id"] as String).startsWith("$duplicateId:") })
            assertExactStoredBytes(repo, root, snapshot(repo))
            val previous = snapshot(repo)
            repo.removePackage(duplicateId); assertEquals(previous, snapshot(repo))
            val removal = repo.applyDraft()
            assertTrue(images(snapshot(repo)).none { (it["id"] as String).startsWith("$duplicateId:") })
            repo.rollbackApply(removal); assertEquals(previous, snapshot(repo))
            assertExactStoredBytes(repo, root, previous)
            apply(repo)
            assertFalse(root.resolve("packages/$duplicateId").exists())
            val tokenBeforeReset = snapshot(repo)
            repo.resetAll(); assertEquals(tokenBeforeReset, snapshot(repo))
            val reset = repo.applyDraft(); assertEquals(emptyList<Any>(), snapshot(repo)["resources"])
            repo.rollbackApply(reset); assertEquals(tokenBeforeReset, snapshot(repo))
            assertExactStoredBytes(repo, root, tokenBeforeReset)
            // Reads racing a real reset may finish their immutable bytes or return null.
            val workers = Executors.newFixedThreadPool(3)
            try {
                val selected = images(tokenBeforeReset).take(12)
                val reads = selected.map { image -> workers.submit(Callable {
                    val bytes = read(repo, tokenBeforeReset, image["id"] as String)
                    if (bytes != null) assertTrue(bytes.take(8).toByteArray().contentEquals(byteArrayOf(-119,80,78,71,13,10,26,10)))
                }) }
                apply(repo)
                reads.forEach { it.get(10, TimeUnit.SECONDS) }
            } finally { workers.shutdownNow() }
            assertEquals(emptyList<Any>(), repo.status()["packages"])
            assertTrue(root.resolve("packages").listFiles()!!.isEmpty())
            assertEquals(emptyList<Any>(), repo.status()["hits"])
            assertEquals(emptyList<Any>(), repo.status()["partialHits"])
            assertEquals(emptyMap<String, Any>(), repo.status()["failures"])
            assertNull(read(repo, tokenBeforeReset, images(tokenBeforeReset).first()["id"] as String))
        } finally {
            fixtures.zip(hashes).forEach { (file, expected) -> assertEquals(file.path, expected, hash(file)) }
        }
    }

    private fun assertExactStoredBytes(repo: GameModRepository, root: File, snapshot: Map<String, Any?>) {
        val index = com.google.gson.JsonParser.parseString(root.resolve("state.json").readText()).asJsonObject
        val files = index["packages"].asJsonArray.flatMap { node ->
            val pack = node.asJsonObject
            pack["resources"].asJsonArray.map { resource ->
                val value = resource.asJsonObject
                value["id"].asString to root.resolve("packages/${pack["id"].asString}/${value["relativeFile"].asString}")
            }
        }.toMap()
        images(snapshot).forEach { image ->
            val id = image["id"] as String
            assertArrayEquals(image["path"] as String, files.getValue(id).readBytes(), read(repo, snapshot, id))
        }
    }
    private fun snapshot(repo: GameModRepository): Map<String, Any?> = repo.portraitSnapshot()
    private fun read(repo: GameModRepository, snapshot: Map<String, Any?>, id: String): ByteArray? =
        repo.readPortrait(snapshot["token"] as String, id)
    @Suppress("UNCHECKED_CAST") private fun images(snapshot: Map<String, Any?>) = snapshot["resources"] as List<Map<String, Any?>>
    private fun packageIds(repo: GameModRepository) = (repo.status()["packages"] as List<*>).map { (it as Map<*, *>)["id"] as String }
    private fun resourceIds(repo: GameModRepository) = (repo.status()["packages"] as List<*>).flatMap {
        ((it as Map<*, *>)["resources"] as List<*>).filter { (it as Map<*, *>)["supported"] == true }.map { (it as Map<*, *>)["id"] as String }
    }
    private fun config(repo: GameModRepository) = mapOf("master" to true, "order" to packageIds(repo),
        "enabledPackages" to packageIds(repo), "enabledResources" to resourceIds(repo))
    private fun apply(repo: GameModRepository) = repo.finishApply(repo.applyDraft())
    private fun hash(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
}
