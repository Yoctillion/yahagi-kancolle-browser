package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class GameModAudioTest {
    @get:Rule val temporary = TemporaryFolder()
    private val path = "kcs/sound/kcsecret123/107404.mp3"
    private val url get() = "https://w15p.kancolle-server.com/$path?version=1"
    private val bytes get() = ByteArray(417 * 4).also { data -> repeat(4) { i ->
        byteArrayOf(-1, -5, -112, 0).copyInto(data, i * 417)
    } }

    @Test fun `only numeric legacy official audio paths are supported`() {
        val repo = GameModRepository(temporary.newFolder())
        val preview = repo.preflight(zip(mapOf(path.replace(".mp3", ".hack.mp3") to bytes,
            "kcs2/sound/kcsecret123/1.mp3" to bytes, "kcs/sound/kcsecret123/原备份.mp3" to bytes,
            "kcs/sound/kcsecret123/备份.wav" to "RIFF".toByteArray())), "voice.zip")
        assertEquals(1, preview["supportedCount"]); assertEquals(3, preview["unsupportedCount"])
        val pack = repo.commitImport(preview["token"] as String)
        val resources = pack["resources"] as List<*>
        assertEquals(setOf("audio_path_unsupported", "audio_filename_unsupported"),
            resources.map { (it as Map<*, *>)["reason"] }.filterNotNull().toSet())
    }

    @Test fun `full audio GET is exact and HEAD never records a body read`() {
        val repo = enabled()
        val head = repo.openResource(url, "HEAD", mapOf("Range" to "bytes=0-4"))!!
        assertEquals(200, head.statusCode); assertEquals("audio/mpeg", head.mimeType)
        assertEquals(bytes.size.toString(), head.headers["Content-Length"])
        assertEquals(-1, head.inputStream.use { it.read() })
        assertEquals(emptyList<String>(), repo.status()["hits"])
        assertEquals(emptyList<String>(), repo.status()["partialHits"])
        val response = repo.openResource(url, "GET", emptyMap())!!
        assertEquals("bytes", response.headers["Accept-Ranges"])
        assertArrayEquals(bytes, response.inputStream.use { it.readBytes() })
        assertEquals(1, (repo.status()["hits"] as List<*>).size)
        assertEquals(1, (repo.status()["partialHits"] as List<*>).size)
    }

    @Test fun `single closed open suffix ranges clamp and return exact bounded bytes`() {
        listOf("bytes=0-9" to (0..9), "bytes=10-" to (10 until bytes.size),
            "bytes=-11" to (bytes.size - 11 until bytes.size), "bytes=4-999999" to (4 until bytes.size)).forEach { (header, range) ->
            val repo = enabled()
            val response = repo.openResource(url, "GET", mapOf("rAnGe" to header))!!
            assertEquals(206, response.statusCode)
            assertEquals("bytes ${range.first}-${range.last}/${bytes.size}", response.headers["Content-Range"])
            assertEquals(range.count().toString(), response.headers["Content-Length"])
            assertArrayEquals(bytes.copyOfRange(range.first, range.last + 1), response.inputStream.use { it.readBytes() })
            assertEquals(emptyList<String>(), repo.status()["hits"])
            assertEquals(1, (repo.status()["partialHits"] as List<*>).size)
        }
    }

    @Test fun `unsatisfiable ranges return 416 while malformed multiple and If-Range use full 200`() {
        val repo = enabled()
        listOf("bytes=${bytes.size}-", "bytes=-0", "bytes=999999999999999999999999999-", "bytes=50-10").forEach { range ->
            val response = repo.openResource(url, "GET", mapOf("Range" to range))!!
            assertEquals(range, 416, response.statusCode)
            assertEquals("bytes */${bytes.size}", response.headers["Content-Range"])
            assertEquals(0, response.inputStream.use { it.readBytes().size })
        }
        listOf("garbage", "bytes=0-2,5-8", "bytes=a-b", "items=0-2", "bytes=--").forEach { range ->
            val response = repo.openResource(url, "GET", mapOf("Range" to range))!!
            assertEquals(200, response.statusCode); assertArrayEquals(bytes, response.inputStream.use { it.readBytes() })
        }
        val conditional = repo.openResource(url, "GET", mapOf("Range" to "bytes=0-9", "If-Range" to "\"unmatched\""))!!
        assertEquals(200, conditional.statusCode); assertArrayEquals(bytes, conditional.inputStream.use { it.readBytes() })
    }

    @Test fun `partial read does not imply full load and complete ranges must cover every byte`() {
        val repo = enabled()
        repo.openResource(url, "GET", mapOf("Range" to "bytes=0-99"))!!.inputStream.use { it.read() }
        assertEquals(1, (repo.status()["partialHits"] as List<*>).size)
        assertEquals(emptyList<String>(), repo.status()["hits"])
        fun consume(range: String) = repo.openResource(url, "GET", mapOf("Range" to range))!!.inputStream.use { it.readBytes() }
        consume("bytes=100-"); consume("bytes=0-50"); consume("bytes=0-50")
        assertEquals(emptyList<String>(), repo.status()["hits"])
        consume("bytes=51-99")
        assertEquals(1, (repo.status()["hits"] as List<*>).size)
        apply(repo)
        assertEquals(emptyList<String>(), repo.status()["partialHits"])
        assertEquals(emptyList<String>(), repo.status()["hits"])
    }

    @Test fun `old audio range survives reset without contaminating new session and restart is durable`() {
        val root = temporary.newFolder(); val repo = enabled(root)
        val old = repo.openResource(url, "GET", mapOf("Range" to "bytes=10-99"))!!.inputStream
        repo.resetAll(); apply(repo)
        assertNull(repo.openResource(url, "GET", emptyMap()))
        assertArrayEquals(bytes.copyOfRange(10, 100), old.use { it.readBytes() })
        assertEquals(emptyList<String>(), repo.status()["partialHits"])
        assertEquals(emptyList<String>(), repo.status()["hits"])
        assertNull(GameModRepository(root).openResource(url, "GET", emptyMap()))
        val activeRoot = temporary.newFolder(); enabled(activeRoot)
        assertArrayEquals(bytes, GameModRepository(activeRoot).openResource(url, "GET", emptyMap())!!.inputStream.use { it.readBytes() })
    }

    @Test fun `audio requests reject wrong hosts paths queries methods and encoded traversal`() {
        val repo = enabled()
        listOf(url.replace("https:", "http:"), url.replace("w15p.kancolle-server.com", "evil.test"),
            url + "&extra=1", url.replace("kcs/sound", "kcs2/sound"), url.replace("107404", "%31%30%37%34%30%34"),
            url.replace("107404", "../107404")).forEach { assertNull(it, repo.openResource(it, "GET", emptyMap())) }
        assertNull(repo.openResource(url, "POST", emptyMap()))
    }

    @Test fun `bad mp3 cannot be imported as a supported voice`() {
        val repo = GameModRepository(temporary.newFolder())
        try { repo.preflight(zip(mapOf(path to "RIFFpretendMP3".toByteArray())), "bad.zip"); fail("disguised audio") }
        catch (error: GameModException) { assertEquals("invalid_audio", error.code) }
    }

    private fun enabled(root: java.io.File = temporary.newFolder()): GameModRepository {
        val repo = GameModRepository(root)
        val preview = repo.preflight(zip(mapOf(path to bytes)), "voice.zip")
        val pack = repo.commitImport(preview["token"] as String)
        val id = pack["id"] as String
        val resource = ((pack["resources"] as List<*>).single() as Map<*, *>)["id"] as String
        repo.saveDraft(mapOf("master" to true, "order" to listOf(id), "enabledPackages" to listOf(id), "enabledResources" to listOf(resource)))
        apply(repo); return repo
    }
    private fun apply(repo: GameModRepository) = repo.finishApply(repo.applyDraft())
    private fun zip(files: Map<String, ByteArray>) = ByteArrayOutputStream().also { output ->
        ZipOutputStream(output).use { zip -> files.forEach { (name, data) -> zip.putNextEntry(ZipEntry(name)); zip.write(data); zip.closeEntry() } }
    }.toByteArray().inputStream()
}
