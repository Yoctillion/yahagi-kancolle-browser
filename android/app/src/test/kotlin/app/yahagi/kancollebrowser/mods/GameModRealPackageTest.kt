package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import com.google.gson.Gson
import com.google.gson.JsonParser
import java.net.URLEncoder
import java.nio.ByteBuffer
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/**
 * Optional real-file audit: set YAHAGI_REAL_MOD_ZIP to a KiddAutomata ZIP containing
 * coordinate-dependent ship PNGs. The source ZIP is never modified or checked in.
 * Original-package safety and a PNG-only diagnostic derived in memory are separate tests.
 */
@RunWith(Parameterized::class)
class GameModRealPackageTest(private val round: Int) {
    @get:Rule val temporary = TemporaryFolder()
    private lateinit var source: File
    private lateinit var images: List<SourceImage>
    private var originalFileCount = 0
    private var coordinateCount = 0
    private lateinit var originalSha256: String

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "round {0}")
        fun rounds(): List<Array<Any>> = (1..3).map { arrayOf<Any>(it) }
    }

    @Before fun readOptionalFixture() {
        val configured = System.getenv("YAHAGI_REAL_MOD_ZIP")?.takeIf { it.isNotBlank() }
        assumeTrue("Set YAHAGI_REAL_MOD_ZIP to run the optional real-package audit", configured != null)
        source = File(configured!!)
        assertTrue("Configured real ZIP does not exist", source.isFile)
        originalSha256 = sha256(source)
        ZipFile(source).use { zip ->
            val files = zip.entries().asSequence().filterNot { it.isDirectory }.toList()
            originalFileCount = files.size
            coordinateCount = files.count { it.name.endsWith(".config.ini") || it.name.endsWith(".config.json") }
            images = files.filter { it.name.endsWith(".png") }.map { entry ->
                val target = entry.name.replace('\\', '/').removePrefix("cache/").replace(Regex("\\.hack\\.png$"), ".png")
                SourceImage(entry.name, target, zip.getInputStream(entry).use { it.readBytes() })
            }
        }
        assertTrue("The audit fixture must contain full ship PNGs", images.isNotEmpty())
        assertTrue("The original-package safety case requires coordinate metadata", coordinateCount > 0)
    }

    @After fun originalArchiveIsUnchanged() {
        if (::source.isInitialized && ::originalSha256.isInitialized) {
            assertEquals("Real fixture must remain unchanged", originalSha256, sha256(source))
        }
    }

    @Test fun `original PNG and merged coordinates work through endpoint acknowledgement and restart`() {
        val root = temporary.newFolder("original")
        val repo = GameModRepository(root)
        val cancelled = preflightOriginal(repo)
        assertOriginalPreview(cancelled)
        repo.discardImport(cancelled["token"] as String)
        expectCode("invalid_token") { repo.commitImport(cancelled["token"] as String) }
        assertTrue(packages(repo).isEmpty())
        assertTrue(root.resolve("staging").listFiles()!!.isEmpty())

        val preview = preflightOriginal(repo)
        assertOriginalPreview(preview)
        repo.commitImport(preview["token"] as String)
        val entry = packages(repo).single()
        val resources = resources(entry)
        assertEquals(images.size + 1, resources.size)
        val coordinate = resources.single { it["kind"] == "coordinates" }
        assertEquals(coordinateCount, (coordinate["sourcePaths"] as List<*>).size)
        assertEquals(15, (coordinate["targetPaths"] as List<*>).size)
        assertTrue(resources.all { it["supported"] == true })
        images.forEach { assertNull(repo.openResource(url(it.target), "GET", emptyMap())) }
        repo.saveDraft(config(repo)); apply(repo)
        assertActualBytes(repo)
        assertFalse((repo.status()["hits"] as List<*>).contains(coordinate["id"]))
        val endpoint = GameModCoordinateEndpoint(repo::activeCoordinateSnapshot, repo::recordCoordinateResult)
        val response = endpoint.open("https://w15p.kancolle-server.com/__yahagi_mods__/coordinates.json", "GET")!!
        val payload = JsonParser.parseString(response.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }).asJsonObject
        val ship = payload["ships"].asJsonObject["607"].asJsonObject
        assertEquals(listOf(180,180), ship["graph"].asJsonObject["api_boko_n"].asJsonArray.map { it.asInt })
        assertEquals(listOf(20,240), ship["graph"].asJsonObject["api_boko_d"].asJsonArray.map { it.asInt })
        val ack = mapOf("sessionId" to payload["sessionId"].asLong, "token" to payload["token"].asString,
            "resourceIds" to ship["resourceIds"].asJsonArray.map { it.asString })
        val report = endpoint.open("https://w15p.kancolle-server.com/__yahagi_mods__/coordinates-report?payload=" + URLEncoder.encode(Gson().toJson(ack), "UTF-8"), "GET")!!
        assertEquals(200, report.statusCode); report.inputStream.close()
        assertEquals(resources.map { it["id"] }.toSet(), (repo.status()["hits"] as List<*>).toSet())

        val abandoned = preflightOriginal(repo)
        val restored = GameModRepository(root)
        assertEquals(repo.status()["draft"], restored.status()["draft"])
        assertEquals(repo.status()["applied"], restored.status()["applied"])
        assertEquals(entry["id"], packages(restored).single()["id"])
        expectCode("invalid_token") { restored.commitImport(abandoned["token"] as String) }
        assertTrue(root.resolve("staging").listFiles()!!.isEmpty())
        assertTrue(resources(packages(restored).single()).all { it["supported"] == true })
        assertEquals(15, (((restored.activeCoordinateSnapshot()["ships"] as Map<*, *>)["607"] as Map<*, *>)["graph"] as Map<*, *>).size)
        println("real original round=$round name=${source.name} sourceFiles=$originalFileCount logicalResources=${resources.size} images=${images.size} coordinateFormats=$coordinateCount mergedCoordinateUnits=1 fields=15 endpointAck/restart=passed")
    }

    @Test fun `derived independent PNG bytes survive package resource master toggles and restart`() {
        val root = temporary.newFolder("independent-pngs")
        val repo = GameModRepository(root)
        val entry = importDerived(repo)
        val packageId = entry["id"] as String
        val selected = resources(entry).map { it["id"] as String }.toSet()
        assertEquals(false, (repo.status()["draft"] as Map<*, *>)["master"])
        assertEquals(emptyList<String>(), (repo.status()["draft"] as Map<*, *>)["enabledPackages"])
        assertEquals(selected, ((repo.status()["draft"] as Map<*, *>)["enabledResources"] as List<*>).toSet())
        repo.saveDraft(config(repo, enabled = emptySet(), selected = selected)); apply(repo)
        images.forEach { assertNull(repo.openResource(url(it.target), "GET", emptyMap())) }
        repo.saveDraft(config(repo, enabled = setOf(packageId), selected = emptySet())); apply(repo)
        images.forEach { assertNull(repo.openResource(url(it.target), "GET", emptyMap())) }

        repo.saveDraft(config(repo)); apply(repo)
        assertActualBytes(repo)
        assertEquals(selected, (repo.status()["hits"] as List<*>).toSet())
        assertActualBytes(repo)
        assertEquals(selected.size, (repo.status()["hits"] as List<*>).size)

        val disabled = resources(entry).first()["id"] as String
        val disabledPath = resources(entry).first()["path"] as String
        repo.saveDraft(config(repo, selected = selected - disabled))
        assertActualBytes(repo) // Draft edits cannot change the current response snapshot.
        apply(repo)
        images.forEach { image ->
            if (image.target == disabledPath) assertNull(repo.openResource(url(image.target), "GET", emptyMap()))
            else assertBytes(repo, image)
        }
        repo.saveDraft(config(repo, master = false)); apply(repo)
        images.forEach { assertNull(repo.openResource(url(it.target), "GET", emptyMap())) }
        val disabledRestart = GameModRepository(root)
        assertEquals(repo.status()["draft"], disabledRestart.status()["draft"])
        assertEquals(repo.status()["applied"], disabledRestart.status()["applied"])
        images.forEach { assertNull(disabledRestart.openResource(url(it.target), "GET", emptyMap())) }
        disabledRestart.saveDraft(config(disabledRestart)); apply(disabledRestart)
        val enabledRestart = GameModRepository(root)
        assertActualBytes(enabledRestart)
        assertEquals(selected, (enabledRestart.status()["hits"] as List<*>).toSet())
        println("real PNG-only diagnostic round=$round resources=${images.size} package/resource/master/restart=passed byteIdentity=passed")
    }

    @Test fun `derived duplicate packages obey priority and staged deletion preserves an old stream`() {
        val repo = GameModRepository(temporary.newFolder("conflicts"))
        val first = importDerived(repo)
        val second = importDerived(repo)
        val firstId = first["id"] as String
        val secondId = second["id"] as String
        val firstByPath = resources(first).associate { it["path"] as String to it["id"] as String }
        val secondByPath = resources(second).associate { it["path"] as String to it["id"] as String }
        repo.saveDraft(config(repo)); apply(repo)
        assertEquals(firstByPath, repo.status()["activeWinners"])
        val oldStream = repo.openResource(url(images.first().target), "GET", emptyMap())!!.inputStream
        try {
            repo.saveDraft(config(repo, order = listOf(secondId, firstId)))
            assertEquals(secondByPath, repo.status()["winners"])
            assertEquals(firstByPath, repo.status()["activeWinners"])
            apply(repo)
            assertEquals(secondByPath, repo.status()["activeWinners"])
            assertActualBytes(repo)
            val selected = allResourceIds(repo) - secondByPath.getValue(images.first().target)
            repo.saveDraft(config(repo, order = listOf(secondId, firstId), selected = selected)); apply(repo)
            assertEquals(firstByPath.getValue(images.first().target), (repo.status()["activeWinners"] as Map<*, *>)[images.first().target])
            repo.removePackage(firstId)
            assertTrue(packages(repo).first { it["id"] == firstId }["pendingRemoval"] as Boolean)
            assertBytes(repo, images.first())
            apply(repo)
            assertNull(repo.openResource(url(images.first().target), "GET", emptyMap()))
            val hitsBefore = repo.status()["hits"]
            assertArrayEquals(images.first().bytes, oldStream.readBytes())
            assertEquals(hitsBefore, repo.status()["hits"])
            repo.removePackage(secondId); apply(repo)
            assertTrue(packages(repo).isEmpty())
            images.forEach { assertNull(repo.openResource(url(it.target), "GET", emptyMap())) }
        } finally { oldStream.close() }
        println("real PNG-only diagnostic round=$round duplicatePackages=2 priority/resourceFallback/stagedDelete/oldStream=passed")
    }

    @Test fun `derived reset and cancelled preparation preserve an outside ordinary cache file`() {
        val root = temporary.newFolder("mods")
        val outside = temporary.root.resolve("ordinary-cache/official.png").apply { parentFile!!.mkdirs(); writeBytes(images.first().bytes) }
        val repo = GameModRepository(root)
        importDerived(repo); repo.saveDraft(config(repo)); apply(repo)
        assertActualBytes(repo)
        repo.resetAll()
        assertEquals(true, repo.status()["pending"])
        assertActualBytes(repo)
        val cancelled = repo.prepareApply()
        assertActualBytes(repo)
        repo.cancelPreparedApply(cancelled)
        assertEquals(true, repo.status()["pending"])
        assertActualBytes(repo)
        apply(repo)
        assertTrue(packages(repo).isEmpty())
        assertFalse(repo.hasActiveOrPending())
        assertArrayEquals(images.first().bytes, outside.readBytes())
        val restored = GameModRepository(root)
        assertFalse(restored.hasActiveOrPending())
        images.forEach { assertNull(restored.openResource(url(it.target), "GET", emptyMap())) }
        importDerived(restored); restored.saveDraft(config(restored)); apply(restored)
        assertActualBytes(restored)
        restored.resetAll(); apply(restored)
        assertArrayEquals(images.first().bytes, outside.readBytes())
        println("real PNG-only diagnostic round=$round reset/cancelPreparation/reimport=passed outsideCachePreserved=true")
    }

    @Test fun `both real packages coexist through coordinate acknowledgement selective deletion and reset`() {
        val configured = System.getenv("YAHAGI_REAL_VOICE_MOD_ZIP")?.takeIf { it.isNotBlank() }
        assumeTrue("Set YAHAGI_REAL_VOICE_MOD_ZIP for the combined real-package audit", configured != null)
        val voiceSource = File(configured!!)
        assertTrue(voiceSource.isFile)
        val voiceHash = sha256(voiceSource)
        try {
            val voiceContents = ZipFile(voiceSource).use { zip ->
                zip.entries().asSequence().filterNot { it.isDirectory }.associate { entry ->
                    entry.name.replace('\\', '/').removePrefix("cache/")
                        .replace(Regex("\\.hack\\.([A-Za-z0-9]+)$"), ".$1") to
                        zip.getInputStream(entry).use { it.readBytes() }
                }
            }
            val root = temporary.newFolder("combined")
            var repo = GameModRepository(root)
            val original = repo.commitImport(preflightOriginal(repo)["token"] as String)
            val voicePreview = voiceSource.inputStream().use { repo.preflight(it, voiceSource.name) }
            assertEquals(54, voicePreview["supportedCount"])
            assertEquals(5, voicePreview["unsupportedCount"])
            val voice = repo.commitImport(voicePreview["token"] as String)
            val voiceResources = resources(voice).filter { it["supported"] == true }
            val selected = (resources(original) + voiceResources).filter { it["supported"] == true }
                .map { it["id"] as String }.toSet()
            assertEquals(57, selected.size)
            repo.saveDraft(config(repo, selected = selected)); apply(repo)
            assertActualBytes(repo)
            fun assertAllVoices() {
                voiceResources.forEach { resource ->
                    val path = resource["path"] as String
                    val response = repo.openResource(url(path), "GET", emptyMap())!!
                    val raw = voiceContents.getValue(path)
                    val expected = if (path.endsWith(".png")) canonicalPng(raw) else raw
                    assertEquals(if (resource["kind"] == "audio") "audio/mpeg" else "image/png", response.mimeType)
                    assertArrayEquals(path, expected, response.inputStream.use { it.readBytes() })
                }
            }
            assertAllVoices()
            assertEquals(56, (repo.status()["hits"] as List<*>).size)
            val endpoint = GameModCoordinateEndpoint(repo::activeCoordinateSnapshot, repo::recordCoordinateResult)
            val configResponse = endpoint.open("https://w15p.kancolle-server.com/__yahagi_mods__/coordinates.json", "GET")!!
            val payload = JsonParser.parseString(configResponse.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }).asJsonObject
            val ship = payload["ships"].asJsonObject["607"].asJsonObject
            assertEquals(15, ship["graph"].asJsonObject.size())
            val ack = mapOf("sessionId" to payload["sessionId"].asLong, "token" to payload["token"].asString,
                "resourceIds" to ship["resourceIds"].asJsonArray.map { it.asString })
            val report = endpoint.open("https://w15p.kancolle-server.com/__yahagi_mods__/coordinates-report?payload=" +
                URLEncoder.encode(Gson().toJson(ack), "UTF-8"), "GET")!!
            assertEquals(200, report.statusCode); report.inputStream.close()
            assertEquals(selected, (repo.status()["hits"] as List<*>).toSet())
            repo = GameModRepository(root)
            assertEquals(2, packages(repo).size)
            assertTrue((repo.activeCoordinateSnapshot()["ships"] as Map<*, *>).containsKey("607"))
            val oldImage = repo.openResource(url(images.first().target), "GET", emptyMap())!!.inputStream
            try {
                repo.removePackage(original["id"] as String)
                assertEquals(2, packages(repo).size)
                apply(repo)
                assertEquals(voice["id"], packages(repo).single()["id"])
                assertEquals(54, resources(packages(repo).single()).count { it["supported"] == true })
                assertTrue((repo.activeCoordinateSnapshot()["ships"] as Map<*, *>).isEmpty())
                images.forEach { assertNull(repo.openResource(url(it.target), "GET", emptyMap())) }
                assertAllVoices()
                assertEquals(54, (repo.status()["hits"] as List<*>).size)
                assertArrayEquals(images.first().bytes, oldImage.readBytes())
                assertEquals(54, (repo.status()["hits"] as List<*>).size)
            } finally { oldImage.close() }
            val outside = temporary.root.resolve("combined-ordinary-cache.bin").apply { writeBytes(images.first().bytes) }
            repo.resetAll(); apply(repo)
            assertTrue(packages(repo).isEmpty())
            assertFalse(repo.hasActiveOrPending())
            assertArrayEquals(images.first().bytes, outside.readBytes())
            val restored = GameModRepository(root)
            assertTrue(packages(restored).isEmpty())
            assertTrue((restored.activeCoordinateSnapshot()["ships"] as Map<*, *>).isEmpty())
            voiceResources.forEach { assertNull(restored.openResource(url(it["path"] as String), "GET", emptyMap())) }
            println("combined real round=$round packages=2 supported=57 streamed=56 coordinateAck=1 deleteI47Retains=54 reset/restart/outsideCache=passed")
        } finally { assertEquals("Converted voice fixture must remain unchanged", voiceHash, sha256(voiceSource)) }
    }

    private fun preflightOriginal(repo: GameModRepository) = source.inputStream().use { repo.preflight(it, source.name) }
    private fun assertOriginalPreview(preview: Map<String, Any?>) {
        assertEquals(source.nameWithoutExtension, preview["name"])
        assertEquals(originalFileCount, preview["sourceFileCount"])
        assertEquals(images.size + 1, preview["resourceCount"])
        assertEquals(images.size + 1, preview["supportedCount"])
        assertEquals(0, preview["unsupportedCount"])
        assertFalse((preview["warnings"] as List<*>).contains("coordinates_unsupported"))
    }
    private fun importDerived(repo: GameModRepository): Map<String, Any?> {
        val diagnostic = ByteArrayOutputStream().also { output ->
            ZipOutputStream(output).use { zip -> images.forEach { image ->
                zip.putNextEntry(ZipEntry(image.sourcePath)); zip.write(image.bytes); zip.closeEntry()
            } }
        }.toByteArray()
        val preview = repo.preflight(diagnostic.inputStream(), "PNG-only-diagnostic.zip")
        assertEquals(images.size, preview["supportedCount"])
        assertEquals(0, preview["unsupportedCount"])
        assertEquals(emptyList<String>(), preview["warnings"])
        return repo.commitImport(preview["token"] as String)
    }
    private fun apply(repo: GameModRepository) = repo.finishApply(repo.applyDraft())
    private fun url(path: String) = "https://w15p.kancolle-server.com/$path?version=real-audit"
    private fun assertActualBytes(repo: GameModRepository) = images.forEach { assertBytes(repo, it) }
    private fun assertBytes(repo: GameModRepository, image: SourceImage) {
        val response = repo.openResource(url(image.target), "GET", emptyMap())
        assertNotNull(image.target, response)
        assertEquals(200, response!!.statusCode)
        assertEquals("image/png", response.mimeType)
        assertEquals(image.bytes.size.toString(), response.headers["Content-Length"])
        assertArrayEquals(image.target, image.bytes, response.inputStream.use { it.readBytes() })
    }
    @Suppress("UNCHECKED_CAST") private fun packages(repo: GameModRepository) = repo.status()["packages"] as List<Map<String, Any?>>
    @Suppress("UNCHECKED_CAST") private fun resources(entry: Map<String, Any?>) = entry["resources"] as List<Map<String, Any?>>
    private fun allResourceIds(repo: GameModRepository) = packages(repo).flatMap(::resources).map { it["id"] as String }.toSet()
    private fun config(repo: GameModRepository, master: Boolean = true,
        order: List<String> = packages(repo).filterNot { it["pendingRemoval"] == true }.map { it["id"] as String },
        enabled: Set<String> = order.toSet(), selected: Set<String> = allResourceIds(repo)) = mapOf(
            "master" to master, "order" to order, "enabledPackages" to enabled.toList(), "enabledResources" to selected.toList())
    private fun expectCode(code: String, operation: () -> Unit) {
        try { operation(); fail("Expected $code") } catch (error: GameModException) { assertEquals(code, error.code) }
    }
    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(8192)
            while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
    private fun canonicalPng(bytes: ByteArray): ByteArray {
        var offset = 8
        while (offset + 12 <= bytes.size) {
            val length = ByteBuffer.wrap(bytes, offset, 4).int
            val type = String(bytes, offset + 4, 4, Charsets.US_ASCII)
            offset += length + 12
            if (type == "IEND") return bytes.copyOf(offset)
        }
        throw AssertionError("Fixture has no PNG end")
    }
    private data class SourceImage(val sourcePath: String, val target: String, val bytes: ByteArray)
}
