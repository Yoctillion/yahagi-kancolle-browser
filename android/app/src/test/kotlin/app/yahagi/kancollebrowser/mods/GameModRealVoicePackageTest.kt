package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.File
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.zip.ZipFile

/** Optional converted-ZIP integration fixture; the application itself continues to accept ZIP only. */
@RunWith(Parameterized::class)
class GameModRealVoicePackageTest(private val round: Int) {
    @get:Rule val temporary = TemporaryFolder()
    private lateinit var source: File
    private lateinit var sourceHash: String
    private lateinit var contents: Map<String, ByteArray>
    companion object {
        @JvmStatic @Parameterized.Parameters(name = "voice round {0}")
        fun rounds(): List<Array<Any>> = (1..3).map { arrayOf<Any>(it) }
    }
    @Before fun readFixture() {
        val configured = System.getenv("YAHAGI_REAL_VOICE_MOD_ZIP")?.takeIf { it.isNotBlank() }
        assumeTrue("Set YAHAGI_REAL_VOICE_MOD_ZIP for the optional converted voice ZIP audit", configured != null)
        source = File(configured!!); assertTrue(source.isFile); sourceHash = hash(source)
        contents = ZipFile(source).use { zip -> zip.entries().asSequence().filterNot { it.isDirectory }.associate { entry ->
            entry.name.removePrefix("cache/").replace(Regex("\\.hack\\.([A-Za-z0-9]+)$"), ".$1") to zip.getInputStream(entry).use { it.readBytes() }
        } }
    }
    @After fun originalConvertedFixtureIsUnchanged() {
        if (::sourceHash.isInitialized) assertEquals(sourceHash, hash(source))
    }

    @Test fun `actual converted package supports images numeric voices ranges conflicts removal and restart`() {
        val root = temporary.newFolder("voice-mods")
        var repo = GameModRepository(root)
        val first = importPackage(repo)
        val firstId = first["id"] as String
        val supported = resources(first).filter { it["supported"] == true }
        val voices = supported.filter { it["kind"] == "audio" }
        val pngs = supported.filter { it["kind"] == "ship" || it["kind"] == "image" }
        assertEquals(25, voices.size); assertEquals(29, pngs.size)
        assertEquals(5, resources(first).count { it["supported"] == false })
        assertEquals(4, resources(first).count { it["reason"] == "audio_filename_unsupported" })
        assertEquals(0, resources(first).count { it["reason"] == "audio_format_unsupported" })
        repo.saveDraft(config(repo)); apply(repo)
        voices.forEach { resource ->
            val head = repo.openResource(url(resource["path"] as String), "HEAD", mapOf("Range" to "bytes=0-9"))!!
            assertEquals(200, head.statusCode); assertEquals("audio/mpeg", head.mimeType)
            assertEquals(-1, head.inputStream.use { it.read() })
        }
        assertEquals(emptyList<String>(), repo.status()["partialHits"])
        assertEquals(emptyList<String>(), repo.status()["hits"])
        val voice = voices.first(); val voicePath = voice["path"] as String; val voiceBytes = contents.getValue(voicePath)
        fun range(header: String) = repo.openResource(url(voicePath), "GET", mapOf("Range" to header))!!
        val begin = range("bytes=0-99")
        assertEquals(206, begin.statusCode); assertArrayEquals(voiceBytes.copyOfRange(0, 100), begin.inputStream.use { it.readBytes() })
        assertEquals(listOf(voice["id"]), repo.status()["partialHits"])
        assertEquals(emptyList<String>(), repo.status()["hits"])
        val rest = range("bytes=100-")
        assertArrayEquals(voiceBytes.copyOfRange(100, voiceBytes.size), rest.inputStream.use { it.readBytes() })
        assertEquals(listOf(voice["id"]), repo.status()["hits"])
        val suffix = range("bytes=-128")
        assertEquals(206, suffix.statusCode); assertArrayEquals(voiceBytes.takeLast(128).toByteArray(), suffix.inputStream.use { it.readBytes() })
        val invalid = range("bytes=${voiceBytes.size}-")
        assertEquals(416, invalid.statusCode); assertEquals(0, invalid.inputStream.use { it.readBytes().size })
        supported.forEach { resource -> assertContent(repo, resource) }
        assertEquals(54, (repo.status()["hits"] as List<*>).size)
        assertEquals(25, (repo.status()["partialHits"] as List<*>).size)
        resources(first).filter { it["supported"] == false }.forEach { resource ->
            assertNull(repo.openResource(url(resource["path"] as String), "GET", emptyMap()))
        }
        val selected = supported.map { it["id"] as String }.toSet()
        repo.saveDraft(config(repo, selected = selected - (voice["id"] as String))); apply(repo)
        assertNull(repo.openResource(url(voicePath), "GET", emptyMap()))
        repo.saveDraft(config(repo, master = false)); apply(repo)
        assertNull(repo.openResource(url(voicePath), "GET", emptyMap()))
        repo.saveDraft(config(repo)); apply(repo)
        repo = GameModRepository(root)
        assertContent(repo, voice)

        val second = importPackage(repo); val secondId = second["id"] as String
        repo.saveDraft(config(repo, order = listOf(secondId, firstId))); apply(repo)
        val secondVoiceId = resources(second).first { it["path"] == voicePath }["id"] as String
        assertEquals(secondVoiceId, (repo.status()["activeWinners"] as Map<*, *>)[voicePath])
        val old = range("bytes=10-99").inputStream
        try {
            repo.removePackage(secondId)
            assertEquals(secondVoiceId, (repo.status()["activeWinners"] as Map<*, *>)[voicePath])
            apply(repo)
            assertEquals(voice["id"], (repo.status()["activeWinners"] as Map<*, *>)[voicePath])
            assertArrayEquals(voiceBytes.copyOfRange(10, 100), old.readBytes())
            assertEquals(emptyList<String>(), repo.status()["partialHits"])
        } finally { old.close() }
        val ordinary = temporary.root.resolve("ordinary-cache.bin").apply { writeBytes(voiceBytes) }
        repo.resetAll(); apply(repo)
        assertFalse(repo.hasActiveOrPending())
        assertArrayEquals(voiceBytes, ordinary.readBytes())
        assertNull(GameModRepository(root).openResource(url(voicePath), "GET", emptyMap()))
        println("voice real round=$round files=59 supported=54 PNG=29 numericMP3=25 unsupported=5 exactBytes/ranges/coverage/toggles/conflicts/delete/reset/restart=passed")
    }

    @Test fun `original 7z gets explicit conversion response without changing source`() {
        val configured = System.getenv("YAHAGI_REAL_VOICE_SOURCE_7Z")?.takeIf { it.isNotBlank() }
        assumeTrue("Set YAHAGI_REAL_VOICE_SOURCE_7Z to audit the original 7z signature", configured != null)
        val original = File(configured!!); assertTrue(original.isFile)
        val before = hash(original)
        try {
            val repo = GameModRepository(temporary.newFolder())
            original.inputStream().use { repo.preflight(it, original.name) }
            fail("The application must not treat 7z as ZIP")
        } catch (error: GameModException) { assertEquals("seven_zip_unsupported", error.code) }
        assertEquals(before, hash(original))
    }

    private fun importPackage(repo: GameModRepository): Map<String, Any?> {
        val preview = source.inputStream().use { repo.preflight(it, source.name) }
        assertEquals(source.nameWithoutExtension, preview["name"])
        assertEquals(59, preview["resourceCount"]); assertEquals(54, preview["supportedCount"]); assertEquals(5, preview["unsupportedCount"])
        assertTrue((preview["warnings"] as List<*>).contains("png_trailing_data_removed"))
        return repo.commitImport(preview["token"] as String)
    }
    private fun assertContent(repo: GameModRepository, resource: Map<String, Any?>) {
        val path = resource["path"] as String
        val response = repo.openResource(url(path), "GET", emptyMap())!!
        val raw = contents.getValue(path)
        val expected = if (path.endsWith(".png")) canonicalPng(raw) else raw
        assertEquals(if (path.endsWith(".mp3")) "audio/mpeg" else "image/png", response.mimeType)
        assertEquals(expected.size.toString(), response.headers["Content-Length"])
        assertArrayEquals(path, expected, response.inputStream.use { it.readBytes() })
    }
    private fun canonicalPng(bytes: ByteArray): ByteArray {
        var offset = 8
        while (offset + 12 <= bytes.size) {
            val size = ByteBuffer.wrap(bytes, offset, 4).int
            val type = String(bytes, offset + 4, 4, Charsets.US_ASCII)
            offset += size + 12
            if (type == "IEND") return bytes.copyOf(offset)
        }
        throw AssertionError("Fixture has no valid PNG end")
    }
    @Suppress("UNCHECKED_CAST") private fun packages(repo: GameModRepository) = repo.status()["packages"] as List<Map<String, Any?>>
    @Suppress("UNCHECKED_CAST") private fun resources(pack: Map<String, Any?>) = pack["resources"] as List<Map<String, Any?>>
    private fun config(repo: GameModRepository, master: Boolean = true,
        order: List<String> = packages(repo).filterNot { it["pendingRemoval"] == true }.map { it["id"] as String },
        selected: Set<String> = packages(repo).flatMap(::resources).filter { it["supported"] == true }.map { it["id"] as String }.toSet()) =
        mapOf("master" to master, "order" to order, "enabledPackages" to order, "enabledResources" to selected.toList())
    private fun apply(repo: GameModRepository) = repo.finishApply(repo.applyDraft())
    private fun url(path: String) = "https://w15p.kancolle-server.com/$path?version=voice-audit"
    private fun hash(file: File): String = MessageDigest.getInstance("SHA-256").let { digest ->
        file.inputStream().use { input -> val data = ByteArray(8192); while (true) { val n = input.read(data); if (n < 0) break; digest.update(data, 0, n) } }
        digest.digest().joinToString("") { "%02x".format(it) }
    }
}
