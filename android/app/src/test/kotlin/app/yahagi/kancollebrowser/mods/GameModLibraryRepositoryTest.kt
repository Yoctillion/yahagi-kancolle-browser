package app.yahagi.kancollebrowser.mods

import com.google.gson.JsonParser
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.lang.reflect.InvocationTargetException
import java.util.UUID
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Library updates must never rewrite the files of an already applied session. */
class GameModLibraryRepositoryTest {
    @get:Rule val temporary = TemporaryFolder()
    private val first = "kcs2/resources/ship/full/0001_abcd.png"
    private val second = "kcs2/resources/ship/banner/0001_bcde.png"

    @Test fun `library import starts with disabled package and selected supported resources`() {
        val repo = GameModRepository(temporary.newFolder())
        val id = UUID.randomUUID().toString()
        val imported = libraryImport(repo, id, linkedMapOf(first to png(1)))
        assertEquals(id, imported["id"])
        assertEquals(emptyList<String>(), draft(repo)["enabledPackages"])
        assertEquals(resources(imported).map { it["id"] }, draft(repo)["enabledResources"])
        assertNull(read(repo, first))
    }

    @Test fun `updating preserves resource identity selection and priority by path rather than archive order`() {
        val repo = GameModRepository(temporary.newFolder())
        val a = UUID.randomUUID().toString(); val b = UUID.randomUUID().toString()
        libraryImport(repo, a, linkedMapOf(first to png(1), second to png(2)))
        libraryImport(repo, b, linkedMapOf(first to png(3)))
        val original = resources(packages(repo).first()).associate { it["path"] to it["id"] }
        repo.saveDraft(mapOf("master" to true, "order" to listOf(b, a), "enabledPackages" to listOf(a, b),
            "enabledResources" to listOf(original.getValue(first))))
        apply(repo)
        val extra = "kcs2/img/new.png"
        libraryImport(repo, a, linkedMapOf(second to png(4), extra to png(5), first to png(6)))
        val updated = resources(packages(repo).first()).associate { it["path"] to it["id"] }
        assertEquals(original[first], updated[first]); assertEquals(original[second], updated[second])
        assertEquals(listOf(b, a), draft(repo)["order"])
        assertEquals(listOf(original.getValue(first)), draft(repo)["enabledResources"])
        assertEquals(true, repo.status()["pending"])
    }

    @Test fun `pending update and process restart continue serving old bytes then cancel restores metadata`() {
        val root = temporary.newFolder(); var repo = GameModRepository(root)
        val id = UUID.randomUUID().toString()
        libraryImport(repo, id, linkedMapOf(first to png(1)), "old.zip")
        enable(repo); apply(repo)
        val before = packages(repo).single()
        libraryImport(repo, id, linkedMapOf(first to png(2), second to png(3)), "updated.zip")
        assertArrayEquals(png(1), read(repo, first))
        repo = GameModRepository(root)
        assertArrayEquals(png(1), read(repo, first)); assertEquals(true, repo.status()["pending"])
        repo.cancelChanges()
        assertEquals(before, packages(repo).single()); assertEquals(false, repo.status()["pending"])
        assertArrayEquals(png(1), read(GameModRepository(root), first))
    }

    @Test fun `applied update is immutable and rollback retains old open streams`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        val id = UUID.randomUUID().toString()
        libraryImport(repo, id, linkedMapOf(first to png(1))); enable(repo); apply(repo)
        val old = repo.openResource(url(first), "GET", emptyMap())!!
        libraryImport(repo, id, linkedMapOf(first to png(2)))
        val token = repo.applyDraft()
        assertArrayEquals(png(2), read(repo, first))
        repo.rollbackApply(token)
        assertArrayEquals(png(1), read(repo, first))
        assertArrayEquals(png(1), old.inputStream.use { it.readBytes() })
        assertArrayEquals(png(1), read(GameModRepository(root), first))
        apply(repo)
        assertArrayEquals(png(2), read(GameModRepository(root), first))
    }

    @Test fun `export editable tree preserves unsupported bytes actual wav extension and merged coordinates`() {
        val repo = GameModRepository(temporary.newFolder())
        val id = UUID.randomUUID().toString()
        val wave = wav()
        libraryImport(repo, id, linkedMapOf(first to png(1),
            "kcs/sound/kc1/1.wav" to wave, "notes/readme.txt" to "keep me".toByteArray(),
            "kcs2/resources/ship/0001.config.ini" to "[graph]\nboko_n_left=5\nboko_n_top=-7".toByteArray(),
            "kcs2/resources/ship/0001.config.json" to "{\"api_mst_shipgraph\":{\"api_kaizo_n\":[8,9]}}".toByteArray()))
        val output = temporary.newFolder()
        call(repo, "exportPackageTree", id, output)
        assertArrayEquals(png(1), output.resolve(first).readBytes())
        assertArrayEquals(wave, output.resolve("kcs/sound/kc1/1.wav").readBytes())
        assertFalse(output.resolve("kcs/sound/kc1/1.mp3").exists())
        assertEquals("keep me", output.resolve("notes/readme.txt").readText())
        val reread = GameModRepository(temporary.newFolder())
        val files = output.walkTopDown().filter { it.isFile }.associate { it.relativeTo(output).invariantSeparatorsPath to it.readBytes() }
        libraryImport(reread, id, files)
        val coordinate = resources(packages(reread).single()).single { it["kind"] == "coordinates" }
        assertEquals("coordinates/ship/1", coordinate["path"])
        assertEquals(2, (coordinate["targetPaths"] as List<*>).size)
    }

    @Test fun `last applied configuration restores switches and order using paths after reinstall`() {
        val repo = GameModRepository(temporary.newFolder())
        val a = UUID.randomUUID().toString(); val b = UUID.randomUUID().toString()
        libraryImport(repo, a, linkedMapOf(first to png(1), second to png(2)))
        libraryImport(repo, b, linkedMapOf(first to png(3)))
        val chosen = resources(packages(repo).first()).first()["id"] as String
        repo.saveDraft(mapOf("master" to true, "order" to listOf(b, a), "enabledPackages" to listOf(a), "enabledResources" to listOf(chosen)))
        apply(repo)
        repo.resetAll()
        @Suppress("UNCHECKED_CAST") val saved = call(repo, "exportAppliedConfiguration") as Map<String, Any?>
        assertEquals(listOf(b, a), saved["order"])
        val fresh = GameModRepository(temporary.newFolder())
        libraryImport(fresh, a, linkedMapOf(second to png(2), first to png(1)))
        libraryImport(fresh, b, linkedMapOf(first to png(3)))
        call(fresh, "restoreLibraryConfiguration", saved)
        assertEquals(listOf(b, a), draft(fresh)["order"]); assertEquals(listOf(a), draft(fresh)["enabledPackages"])
        apply(fresh)
        assertArrayEquals(png(1), read(fresh, first)); assertNull(read(fresh, second))
    }

    @Test fun `cancel deletion after update restores applied revision and all switches`() {
        val root = temporary.newFolder(); var repo = GameModRepository(root)
        val id = UUID.randomUUID().toString()
        libraryImport(repo, id, linkedMapOf(first to png(1))); enable(repo); apply(repo)
        repeat(3) {
            libraryImport(repo, id, linkedMapOf(first to png(it + 2)))
            repo.removePackage(id)
            repo = GameModRepository(root)
            repo.cancelChanges()
            assertEquals(false, repo.status()["pending"])
            assertArrayEquals(png(1), read(repo, first))
        }
        repo.resetAll(); apply(repo)
        assertTrue(packages(repo).isEmpty()); assertNull(read(repo, first))
    }

    @Test fun `migration fingerprint persists with applied package and cancel restores previous source hash`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        val preview = repo.preflight(zip(linkedMapOf(first to png(1))), "old.zip")
        val entry = repo.commitImport(preview["token"] as String)
        val id = entry["id"] as String
        enable(repo); apply(repo)
        call(repo, "attachLibraryFingerprint", id, "original-hash")
        val update = repo.preflight(zip(linkedMapOf(first to png(2))), "updated.zip")
        call(repo, "commitLibraryImport", update["token"] as String, id, "new-hash")
        assertEquals("new-hash", packages(repo).single()["sourceFingerprint"])
        val restored = GameModRepository(root); restored.cancelChanges()
        assertEquals("original-hash", packages(restored).single()["sourceFingerprint"])
        assertEquals(false, restored.status()["pending"])
    }

    @Test fun `preflight export writes editable tree without committing or consuming preview`() {
        val repo = GameModRepository(temporary.newFolder())
        val preview = repo.preflight(zip(linkedMapOf(first to png(1))), "cache.zip")
        val token = preview["token"] as String
        val output = temporary.newFolder()
        call(repo, "exportPreflightTree", token, output)
        assertArrayEquals(png(1), output.resolve(first).readBytes())
        assertTrue(packages(repo).isEmpty())
        val id = UUID.randomUUID().toString()
        call(repo, "commitLibraryImport", token, id, "saved-hash")
        assertEquals("saved-hash", packages(repo).single()["sourceFingerprint"])
    }

    @Test fun `legacy saved index migrates applied metadata before the first library update`() {
        val root = temporary.newFolder(); var repo = GameModRepository(root)
        val preview = repo.preflight(zip(linkedMapOf(first to png(1))), "legacy.zip")
        val id = repo.commitImport(preview["token"] as String)["id"] as String
        enable(repo); apply(repo)
        val index = root.resolve("state.json")
        val legacy = JsonParser.parseString(index.readText()).asJsonObject
        legacy.remove("appliedPackages")
        index.writeText(legacy.toString())
        repo = GameModRepository(root)
        assertArrayEquals(png(1), read(repo, first))
        libraryImport(repo, id, linkedMapOf(first to png(2)))
        val restarted = GameModRepository(root)
        assertArrayEquals(png(1), read(restarted, first))
        restarted.cancelChanges()
        assertEquals(false, restarted.status()["pending"])
    }

    @Test fun `old revision files survive apply until the last old stream closes`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        val id = UUID.randomUUID().toString()
        libraryImport(repo, id, linkedMapOf(first to png(1))); enable(repo); apply(repo)
        val old = repo.openResource(url(first), "GET", emptyMap())!!
        libraryImport(repo, id, linkedMapOf(first to png(2))); apply(repo)
        assertEquals(2, root.walkTopDown().count { it.isFile && it.extension == "png" })
        assertArrayEquals(png(1), old.inputStream.use { it.readBytes() })
        assertEquals(1, root.walkTopDown().count { it.isFile && it.extension == "png" })
        assertArrayEquals(png(2), read(repo, first))
    }

    @Test fun `failed update persistence preserves original session and reusable preview`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        val id = UUID.randomUUID().toString()
        libraryImport(repo, id, linkedMapOf(first to png(1))); enable(repo); apply(repo)
        val preview = repo.preflight(zip(linkedMapOf(first to png(2))), "new.zip")
        val index = root.resolve("state.json")
        val saved = index.readText()
        assertTrue(index.delete()); assertTrue(index.mkdir())
        try {
            call(repo, "commitLibraryImport", preview["token"] as String, id)
            fail("An unwritable index must reject the update")
        } catch (error: GameModException) { assertEquals("storage_error", error.code) }
        assertArrayEquals(png(1), read(repo, first))
        assertTrue(index.delete()); index.writeText(saved)
        call(repo, "commitLibraryImport", preview["token"] as String, id)
        apply(repo)
        assertArrayEquals(png(2), read(GameModRepository(root), first))
    }

    @Test fun `deferring published cleanup releases mutation lock and keeps deletion intent durable`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        val a = UUID.randomUUID().toString(); val b = UUID.randomUUID().toString()
        libraryImport(repo, a, linkedMapOf(first to png(1)))
        libraryImport(repo, b, linkedMapOf(first to png(2)))
        enable(repo); apply(repo)
        assertArrayEquals(png(1), read(repo, first))
        repo.removePackage(a)
        val token = repo.applyDraft()
        assertArrayEquals(png(2), read(repo, first))
        call(repo, "deferApplyCleanup", token)
        assertTrue(packages(repo).single { it["id"] == a }["pendingRemoval"] as Boolean)
        assertTrue(root.resolve("packages/$a").isDirectory)
        repo.saveDraft(draft(repo)) // A failed public journal cannot leave the apply reservation held.
        val restarted = GameModRepository(root)
        assertArrayEquals(png(2), read(restarted, first))
        assertEquals(true, restarted.status()["pending"])
        assertTrue(packages(restarted).single { it["id"] == a }["pendingRemoval"] as Boolean)
        apply(restarted)
        assertFalse(root.resolve("packages/$a").exists())
        assertEquals(listOf(b), packages(restarted).map { it["id"] })
        assertArrayEquals(png(2), read(GameModRepository(root), first))
    }

    @Test fun `restore preserves new package resource defaults while saved empty selections stay empty`() {
        val original = GameModRepository(temporary.newFolder())
        val a = UUID.randomUUID().toString(); val b = UUID.randomUUID().toString()
        libraryImport(original, a, linkedMapOf(first to png(1), second to png(2)))
        val chosen = resources(packages(original).single()).single { it["path"] == first }["id"] as String
        original.saveDraft(mapOf("master" to true, "order" to listOf(a), "enabledPackages" to listOf(a), "enabledResources" to listOf(chosen)))
        apply(original)
        @Suppress("UNCHECKED_CAST") val saved = call(original, "exportAppliedConfiguration") as Map<String, Any?>

        val fresh = GameModRepository(temporary.newFolder())
        val newPath = "kcs2/img/a_new.png"
        libraryImport(fresh, a, linkedMapOf(first to png(1), second to png(2), newPath to png(3)))
        libraryImport(fresh, b, linkedMapOf(first to png(4), second to png(5)))
        val aResources = resources(packages(fresh).single { it["id"] == a })
        val bResources = resources(packages(fresh).single { it["id"] == b })
        val firstA = aResources.single { it["path"] == first }["id"] as String
        val bDefaults = bResources.filter { it["supported"] == true }.map { it["id"] as String }
        call(fresh, "restoreLibraryConfiguration", saved)
        assertEquals(listOf(a, b), draft(fresh)["order"])
        assertEquals(listOf(a), draft(fresh)["enabledPackages"])
        assertEquals((listOf(firstA) + bDefaults).toSet(), (draft(fresh)["enabledResources"] as List<*>).toSet())
        assertTrue(aResources.filter { it["path"] != first }.none { it["id"] in (draft(fresh)["enabledResources"] as List<*>) })

        // An explicit empty entry is a user's saved choice, not a missing/new package.
        @Suppress("UNCHECKED_CAST") val selection = saved["enabledResources"] as Map<String, Any?>
        val explicitEmpty = saved + mapOf("order" to listOf(a, b), "enabledResources" to (selection + (b to emptyList<String>())))
        call(fresh, "restoreLibraryConfiguration", explicitEmpty)
        assertEquals(listOf(firstA), draft(fresh)["enabledResources"])
        assertEquals(listOf(a), draft(fresh)["enabledPackages"])
    }

    private fun libraryImport(repo: GameModRepository, id: String, files: Map<String, ByteArray>, name: String = "cache.zip"): Map<*, *> {
        val preview = repo.preflight(zip(files), name)
        return call(repo, "commitLibraryImport", preview["token"] as String, id) as Map<*, *>
    }
    private fun call(repo: GameModRepository, name: String, vararg args: Any): Any? {
        val method = repo.javaClass.methods.singleOrNull { it.name == name && it.parameterCount == args.size }
        assertNotNull("Missing required persistent-library API: $name", method)
        return try { method!!.invoke(repo, *args) } catch (error: InvocationTargetException) { throw error.cause!! }
    }
    @Suppress("UNCHECKED_CAST") private fun packages(repo: GameModRepository) = repo.status()["packages"] as List<Map<String, Any?>>
    @Suppress("UNCHECKED_CAST") private fun resources(entry: Map<*, *>) = entry["resources"] as List<Map<String, Any?>>
    private fun draft(repo: GameModRepository) = repo.status()["draft"] as Map<*, *>
    private fun enable(repo: GameModRepository) {
        val packages = packages(repo)
        repo.saveDraft(mapOf("master" to true, "order" to packages.map { it["id"] },
            "enabledPackages" to packages.map { it["id"] }, "enabledResources" to packages.flatMap { resources(it) }.filter { it["supported"] == true }.map { it["id"] }))
    }
    private fun apply(repo: GameModRepository) = repo.finishApply(repo.applyDraft())
    private fun url(path: String) = "https://w01x.kancolle-server.com/$path?version=1"
    private fun read(repo: GameModRepository, path: String) = repo.openResource(url(path), "GET", emptyMap())?.inputStream?.use { it.readBytes() }
    private fun zip(files: Map<String, ByteArray>) = ByteArrayOutputStream().also { out -> ZipOutputStream(out).use { zip -> files.forEach { (path, bytes) -> zip.putNextEntry(ZipEntry(path)); zip.write(bytes); zip.closeEntry() } } }.toByteArray().inputStream()
    private fun wav(): ByteArray = ByteArrayOutputStream().also { output ->
        val data = DataOutputStream(output)
        fun little(value: Int, bytes: Int) { repeat(bytes) { data.writeByte(value ushr (8 * it)) } }
        data.writeBytes("RIFF"); little(38, 4); data.writeBytes("WAVEfmt "); little(16, 4)
        little(1, 2); little(1, 2); little(8000, 4); little(16000, 4); little(2, 2); little(16, 2)
        data.writeBytes("data"); little(2, 4); little(0, 2)
    }.toByteArray()
    private fun png(red: Int): ByteArray = ByteArrayOutputStream().also { output ->
        val data = DataOutputStream(output); data.write(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
        fun chunk(type: String, bytes: ByteArray) { val kind = type.toByteArray(); data.writeInt(bytes.size); data.write(kind); data.write(bytes); data.writeInt(CRC32().apply { update(kind); update(bytes) }.value.toInt()) }
        chunk("IHDR", ByteArrayOutputStream().also { DataOutputStream(it).apply { writeInt(1); writeInt(1); write(byteArrayOf(8, 6, 0, 0, 0)) } }.toByteArray())
        chunk("IDAT", ByteArrayOutputStream().also { DeflaterOutputStream(it).use { it.write(byteArrayOf(0, red.toByte(), 0, 0, -1)) } }.toByteArray())
        chunk("IEND", byteArrayOf())
    }.toByteArray()
}
