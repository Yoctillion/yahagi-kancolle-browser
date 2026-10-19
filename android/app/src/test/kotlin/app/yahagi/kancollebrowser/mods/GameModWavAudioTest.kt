package app.yahagi.kancollebrowser.mods

import com.google.gson.JsonArray
import com.google.gson.JsonParser
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class GameModWavAudioTest {
    @get:Rule val temporary = TemporaryFolder()
    private val target = "kcs/sound/kcsecret123/107404.mp3"
    private val source = target.removeSuffix(".mp3") + ".wav"
    private val url get() = "https://w15p.kancolle-server.com/$target?version=wav-test"
    private val wave get() = pcmWave()
    private val mp3 get() = ByteArray(417 * 4).also { data -> repeat(4) { index ->
        byteArrayOf(-1, -5, -112, 0).copyInto(data, index * 417)
    } }

    @Test fun `numeric WAV maps to game MP3 target while keeping original source and durable MIME`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        val named = "cache/" + source.replace(".wav", ".hack.wav")
        val pack = import(repo, mapOf(named to wave))
        val resource = resources(pack).single()
        assertEquals(target, resource["path"])
        assertEquals(listOf(named), resource["sourcePaths"])
        assertEquals("audio", resource["kind"])
        assertEquals(true, resource["supported"])
        enable(repo)
        val response = repo.openResource(url, "GET", emptyMap())!!
        assertEquals(200, response.statusCode); assertEquals("audio/wav", response.mimeType)
        assertEquals("audio/wav", response.headers["Content-Type"])
        assertArrayEquals(wave, response.inputStream.use { it.readBytes() })
        assertNull(repo.openResource(url.replace(".mp3", ".wav"), "GET", emptyMap()))
        assertTrue(root.walkTopDown().any { it.isFile && it.extension == "wav" })
        val restored = GameModRepository(root)
        val again = restored.openResource(url, "GET", emptyMap())!!
        assertEquals("audio/wav", again.mimeType)
        assertArrayEquals(wave, again.inputStream.use { it.readBytes() })
    }

    @Test fun `uppercase WAV and hack WAV extensions preserve source names and canonicalize targets`() {
        listOf(source.replace(".wav", ".WAV"), source.replace(".wav", ".hack.WAV")).forEach { name ->
            val repo = GameModRepository(temporary.newFolder())
            val resource = resources(import(repo, mapOf(name to wave))).single()
            assertEquals(target, resource["path"])
            assertEquals(listOf(name), resource["sourcePaths"])
            assertEquals(true, resource["supported"])
            enable(repo)
            val response = repo.openResource(url, "GET", emptyMap())!!
            assertEquals("audio/wav", response.mimeType)
            assertArrayEquals(wave, response.inputStream.use { it.readBytes() })
        }
    }

    @Test fun `WAV HEAD ignores Range and never counts body delivery`() {
        val repo = enabled()
        listOf("bytes=0-7", "bytes=99999999-").forEach { range ->
            val head = repo.openResource(url, "HEAD", mapOf("Range" to range))!!
            assertEquals(200, head.statusCode); assertEquals("audio/wav", head.mimeType)
            assertEquals(wave.size.toString(), head.headers["Content-Length"])
            assertNull(head.headers["Content-Range"])
            assertEquals(0, head.inputStream.use { it.readBytes().size })
        }
        assertEquals(emptyList<String>(), repo.status()["hits"])
        assertEquals(emptyList<String>(), repo.status()["partialHits"])
    }

    @Test fun `WAV closed open and suffix ranges return bounded bytes and real MIME`() {
        val repo = enabled()
        listOf("bytes=0-9" to (0..9), "bytes=10-" to (10 until wave.size),
            "bytes=-11" to (wave.size - 11 until wave.size), "bytes=4-999999" to (4 until wave.size)).forEach { (header, range) ->
            val response = repo.openResource(url, "GET", mapOf("Range" to header))!!
            assertEquals(206, response.statusCode); assertEquals("audio/wav", response.mimeType)
            assertEquals("bytes ${range.first}-${range.last}/${wave.size}", response.headers["Content-Range"])
            assertEquals(range.count().toString(), response.headers["Content-Length"])
            assertArrayEquals(wave.copyOfRange(range.first, range.last + 1), response.inputStream.use { it.readBytes() })
        }
    }

    @Test fun `WAV unsatisfiable range and malformed conditional requests preserve audio semantics`() {
        val repo = enabled()
        val unsatisfiable = repo.openResource(url, "GET", mapOf("Range" to "bytes=${wave.size}-"))!!
        assertEquals(416, unsatisfiable.statusCode); assertEquals("audio/wav", unsatisfiable.mimeType)
        assertEquals("bytes */${wave.size}", unsatisfiable.headers["Content-Range"])
        assertEquals(0, unsatisfiable.inputStream.use { it.readBytes().size })
        listOf(mapOf("Range" to "bytes=0-2,5-8"), mapOf("Range" to "garbage"),
            mapOf("Range" to "bytes=0-9", "If-Range" to "unmatched")).forEach { headers ->
            val response = repo.openResource(url, "GET", headers)!!
            assertEquals(200, response.statusCode); assertEquals("audio/wav", response.mimeType)
            assertArrayEquals(wave, response.inputStream.use { it.readBytes() })
        }
    }

    @Test fun `WAV partial delivery needs complete range coverage for a full hit`() {
        val repo = enabled()
        repo.openResource(url, "GET", mapOf("Range" to "bytes=0-99"))!!.inputStream.use { it.read() }
        assertEquals(1, (repo.status()["partialHits"] as List<*>).size)
        assertEquals(emptyList<String>(), repo.status()["hits"])
        fun read(range: String) = repo.openResource(url, "GET", mapOf("Range" to range))!!.inputStream.use { it.readBytes() }
        read("bytes=100-"); read("bytes=0-50"); read("bytes=0-50")
        assertEquals(emptyList<String>(), repo.status()["hits"])
        read("bytes=51-99")
        assertEquals(1, (repo.status()["hits"] as List<*>).size)
    }

    @Test fun `same package MP3 WAV and hack WAV aliases cannot silently conflict`() {
        listOf(mapOf(target to mp3, source to wave),
            mapOf(source to wave, source.replace(".wav", ".hack.wav") to wave)).forEach { files ->
            val repo = GameModRepository(temporary.newFolder())
            expect("duplicate_resource") { repo.preflight(zip(files), "conflict.zip") }
            assertTrue(packages(repo).isEmpty())
        }
    }

    @Test fun `cross package MP3 and WAV use existing priority and independent switches`() {
        val repo = GameModRepository(temporary.newFolder())
        val wavPack = import(repo, mapOf(source to wave)); val mp3Pack = import(repo, mapOf(target to mp3))
        enable(repo)
        repo.openResource(url, "GET", emptyMap())!!.let { response ->
            assertEquals("audio/wav", response.mimeType); assertArrayEquals(wave, response.inputStream.use { it.readBytes() })
        }
        val reverse = listOf(mp3Pack["id"], wavPack["id"])
        repo.saveDraft(config(repo) + ("order" to reverse)); apply(repo)
        repo.openResource(url, "GET", emptyMap())!!.let { response ->
            assertEquals("audio/mpeg", response.mimeType); assertArrayEquals(mp3, response.inputStream.use { it.readBytes() })
        }
        val mp3Id = resources(mp3Pack).single()["id"]
        val selected = allIds(repo).filterNot { it == mp3Id }
        repo.saveDraft(config(repo) + ("order" to reverse) + ("enabledResources" to selected)); apply(repo)
        assertEquals("audio/wav", repo.openResource(url, "HEAD", emptyMap())!!.mimeType)
    }

    @Test fun `old WAV range survives removal and reset without leaking hits into the next session`() {
        val root = temporary.newFolder(); val repo = enabled(root)
        val old = repo.openResource(url, "GET", mapOf("Range" to "bytes=10-99"))!!.inputStream
        repo.removePackage(packages(repo).single()["id"] as String)
        assertEquals("audio/wav", repo.openResource(url, "HEAD", emptyMap())!!.mimeType)
        apply(repo)
        assertNull(repo.openResource(url, "GET", emptyMap()))
        assertArrayEquals(wave.copyOfRange(10, 100), old.use { it.readBytes() })
        assertEquals(emptyList<String>(), repo.status()["partialHits"])
        assertEquals(emptyList<String>(), repo.status()["hits"])
        assertTrue(packages(GameModRepository(root)).isEmpty())
        import(repo, mapOf(source to wave)); enable(repo)
        val resetStream = repo.openResource(url, "GET", emptyMap())!!.inputStream
        repo.resetAll(); apply(repo)
        assertArrayEquals(wave, resetStream.use { it.readBytes() })
        assertFalse(GameModRepository(root).hasActiveOrPending())
        assertEquals(emptyList<String>(), repo.status()["hits"])
    }

    @Test fun `unnumbered WAVs and nonofficial paths remain unsupported without guessing`() {
        val repo = GameModRepository(temporary.newFolder())
        val pack = import(repo, mapOf("kcs/sound/kcsecret123/击沉.wav" to wave,
            "kcs2/sound/kcsecret123/107404.wav" to wave))
        assertEquals(setOf("audio_filename_unsupported", "audio_path_unsupported"), resources(pack).map { it["reason"] }.toSet())
        assertTrue(resources(pack).all { it["supported"] == false })
        assertEquals(2, resources(pack).size)
        assertEquals(0, ((repo.status()["draft"] as Map<*, *>)["enabledResources"] as List<*>).size)
    }

    @Test fun `legacy unsupported numeric WAV stays unsupported on restart until reimport`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo, mapOf(source to wave))
        val file = root.resolve("state.json")
        val state = JsonParser.parseString(file.readText()).asJsonObject
        val resource = state["packages"].asJsonArray[0].asJsonObject["resources"].asJsonArray[0].asJsonObject
        resource.addProperty("path", source)
        resource.addProperty("supported", false)
        resource.addProperty("reason", "audio_format_unsupported")
        state["draft"].asJsonObject.add("enabledResources", JsonArray())
        file.writeText(state.toString())
        val restored = GameModRepository(root)
        val legacy = resources(packages(restored).single()).single()
        assertEquals(false, legacy["supported"])
        assertEquals("audio_format_unsupported", legacy["reason"])
        assertEquals(source, legacy["path"])
        assertNull(restored.openResource(url, "GET", emptyMap()))
        expect("invalid_config") { restored.saveDraft(config(restored) + ("enabledResources" to listOf(legacy["id"]))) }
        assertArrayEquals(wave, root.walkTopDown().first { it.isFile && it.extension == "wav" }.readBytes())
    }

    @Test fun `WAV only answers official MP3 GET and HEAD URLs`() {
        val repo = enabled()
        listOf(url.replace("https:", "http:"), url.replace("w15p.kancolle-server.com", "evil.test"),
            url + "&extra=1", url.replace("kcs/sound", "kcs2/sound"), url.replace("107404", "%31%30%37%34%30%34"),
            url.replace(".mp3", ".wav")).forEach { assertNull(it, repo.openResource(it, "GET", emptyMap())) }
        assertNull(repo.openResource(url, "POST", emptyMap()))
    }

    @Test fun `numeric disguised WAV is rejected instead of enabled`() {
        val repo = GameModRepository(temporary.newFolder())
        expect("invalid_audio") { repo.preflight(zip(mapOf(source to mp3)), "fake.zip") }
        expect("invalid_audio") { repo.preflight(zip(mapOf(source to wave.copyOf(wave.size - 1))), "truncated.zip") }
    }

    @Test fun `actual extensible float WAV can be explicitly assigned a numeric diagnostic target`() {
        val directory = System.getenv("YAHAGI_REAL_MOD_AUDIO_DIR")?.takeIf { it.isNotBlank() }
        assumeTrue("Set YAHAGI_REAL_MOD_AUDIO_DIR for the optional real WAV audit", directory != null)
        val file = File(directory!!, "kcs/sound/kcxngurirfszwi/击沉.wav")
        assertTrue(file.isFile)
        val original = file.readBytes(); val repo = GameModRepository(temporary.newFolder())
        import(repo, mapOf(source to original)); enable(repo)
        val response = repo.openResource(url, "GET", emptyMap())!!
        assertEquals("audio/wav", response.mimeType)
        assertArrayEquals(original, response.inputStream.use { it.readBytes() })
        assertArrayEquals(original, file.readBytes())
    }

    private fun enabled(root: File = temporary.newFolder()) = GameModRepository(root).also {
        import(it, mapOf(source to wave)); enable(it)
    }
    private fun import(repo: GameModRepository, files: Map<String, ByteArray>): Map<String, Any?> {
        val preview = repo.preflight(zip(files), "wav.zip")
        return repo.commitImport(preview["token"] as String)
    }
    private fun enable(repo: GameModRepository) { repo.saveDraft(config(repo)); apply(repo) }
    private fun apply(repo: GameModRepository) = repo.finishApply(repo.applyDraft())
    @Suppress("UNCHECKED_CAST") private fun packages(repo: GameModRepository) = repo.status()["packages"] as List<Map<String, Any?>>
    @Suppress("UNCHECKED_CAST") private fun resources(pack: Map<String, Any?>) = pack["resources"] as List<Map<String, Any?>>
    private fun allIds(repo: GameModRepository) = packages(repo).flatMap(::resources).filter { it["supported"] == true }.map { it["id"] }
    private fun config(repo: GameModRepository): Map<String, Any> = mapOf("master" to true,
        "order" to packages(repo).map { it["id"]!! }, "enabledPackages" to packages(repo).map { it["id"]!! },
        "enabledResources" to allIds(repo))
    private fun expect(code: String, run: () -> Unit) {
        try { run(); fail("Expected $code") } catch (error: GameModException) { assertEquals(code, error.code) }
    }
    private fun zip(files: Map<String, ByteArray>) = ByteArrayOutputStream().also { output ->
        ZipOutputStream(output).use { zip -> files.forEach { (path, data) -> zip.putNextEntry(ZipEntry(path)); zip.write(data); zip.closeEntry() } }
    }.toByteArray().inputStream()
    private fun pcmWave(): ByteArray {
        val data = ByteArray(512) { ((it * 31) xor (it shr 2)).toByte() }
        return ByteBuffer.allocate(44 + data.size).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray()); putInt(capacity() - 8); put("WAVEfmt ".toByteArray()); putInt(16)
            putShort(1); putShort(1); putInt(8000); putInt(16000); putShort(2); putShort(16)
            put("data".toByteArray()); putInt(data.size); put(data)
        }.array()
    }
}
