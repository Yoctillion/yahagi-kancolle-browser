package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class GameModRepositoryTest {
    @get:Rule val temporary = TemporaryFolder()
    private val target = "kcs2/resources/ship/full/0001_abcd.png"
    private val url get() = "https://w01x.kancolle-server.com/$target?version=1.2.3"

    @Test fun `import is disabled until both package and resource are enabled and applied`() {
        val repo = repository()
        val preview = repo.preflight(zip(target), "cache.zip")
        assertEquals(1, preview["supportedCount"])
        assertEquals(0, packages(repo).size)
        repo.commitImport(preview["token"] as String)
        assertEquals(1, packages(repo).size)
        assertNull(repo.openResource(url, "GET", emptyMap()))
        enable(repo)
        assertNull(repo.openResource(url, "GET", emptyMap()))
        val token = repo.applyDraft()
        repo.finishApply(token)
        assertNotNull(repo.openResource(url, "GET", emptyMap()))
    }

    @Test fun `loaded status requires complete read and belongs to the active session`() {
        val repo = repository(); import(repo); enable(repo); apply(repo)
        val abandoned = repo.openResource(url, "GET", emptyMap())!!
        abandoned.inputStream.read()
        abandoned.inputStream.close()
        assertEquals(emptyList<String>(), repo.status()["hits"])
        val old = repo.openResource(url, "GET", emptyMap())!!
        apply(repo)
        old.inputStream.readBytes(); old.inputStream.close()
        assertEquals(emptyList<String>(), repo.status()["hits"])
        repeat(2) { repo.openResource(url, "GET", emptyMap())!!.inputStream.use { it.readBytes() } }
        assertEquals(listOf(resourceId(repo)), repo.status()["hits"])
    }

    @Test fun `draft changes and staged removal keep active responses until apply`() {
        val repo = repository(); import(repo); enable(repo); apply(repo)
        val old = repo.openResource(url, "GET", emptyMap())!!
        repo.removePackage(packageId(repo))
        assertTrue(packages(repo).single()["pendingRemoval"] as Boolean)
        assertNotNull(repo.openResource(url, "GET", emptyMap()))
        apply(repo)
        assertNull(repo.openResource(url, "GET", emptyMap()))
        assertTrue(packages(repo).isEmpty())
        assertArrayEquals(png(), old.inputStream.use { it.readBytes() })
    }

    @Test fun `rollback restores prior session and durable config`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); enable(repo); apply(repo)
        val before = repo.status()["sessionId"]
        repo.resetAll()
        val token = repo.applyDraft()
        assertNull(repo.openResource(url, "GET", emptyMap()))
        repo.rollbackApply(token)
        assertEquals(before, repo.status()["sessionId"])
        assertNotNull(repo.openResource(url, "GET", emptyMap()))
        assertNotNull(GameModRepository(root).openResource(url, "GET", emptyMap()))
        assertEquals(true, repo.status()["pending"])
    }

    @Test fun `persistent drafts and applied config remain independent across restart`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); enable(repo); apply(repo)
        repo.saveDraft(config(repo, master = false))
        val restored = GameModRepository(root)
        assertEquals(false, (restored.status()["draft"] as Map<*, *>)["master"])
        assertEquals(true, (restored.status()["applied"] as Map<*, *>)["master"])
        assertNotNull(restored.openResource(url, "GET", emptyMap()))
        apply(restored)
        assertNull(restored.openResource(url, "GET", emptyMap()))
    }

    @Test fun `first ordered package wins and disabling its resource reveals later package`() {
        val repo = repository(); import(repo); import(repo)
        val packages = packages(repo)
        val ids = packages.map { it["id"] as String }
        val resources = packages.map { (it["resources"] as List<*>).single() as Map<*, *> }.map { it["id"] as String }
        repo.saveDraft(mapOf("master" to true, "order" to ids, "enabledPackages" to ids, "enabledResources" to resources))
        assertEquals(resources.first(), (repo.status()["winners"] as Map<*, *>)[target])
        repo.saveDraft(mapOf("master" to true, "order" to ids, "enabledPackages" to ids, "enabledResources" to resources.takeLast(1)))
        assertEquals(resources.last(), (repo.status()["winners"] as Map<*, *>)[target])
    }

    @Test fun `turning a resource off and back on clears pending despite selection order`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); import(repo)
        val ids = packages(repo).map { it["id"] as String }
        val resources = packages(repo).map { ((it["resources"] as List<*>).single() as Map<*, *>)["id"] as String }
        val config = mapOf("master" to true, "order" to ids, "enabledPackages" to ids, "enabledResources" to resources)
        repo.saveDraft(config); apply(repo)
        val session = repo.status()["sessionId"]
        val activeWinners = repo.status()["activeWinners"]
        repo.saveDraft(config + ("enabledResources" to resources.drop(1)))
        assertEquals(true, repo.status()["pending"])
        repo.saveDraft(config + ("enabledResources" to resources.reversed()))
        assertEquals(false, repo.status()["pending"])
        assertEquals(session, repo.status()["sessionId"])
        assertEquals(activeWinners, repo.status()["activeWinners"])
        assertEquals(activeWinners, repo.status()["winners"])
        assertEquals(false, GameModRepository(root).status()["pending"])
    }

    @Test fun `enabled package order is immaterial for pending and inactive checks across restart`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); import(repo)
        val ids = packages(repo).map { it["id"] as String }
        val resources = packages(repo).map { ((it["resources"] as List<*>).single() as Map<*, *>)["id"] as String }
        val config = mapOf("master" to false, "order" to ids, "enabledPackages" to ids, "enabledResources" to resources)
        repo.saveDraft(config); apply(repo)
        repo.saveDraft(config + ("enabledPackages" to ids.drop(1)))
        assertEquals(true, repo.status()["pending"])
        repo.saveDraft(config + ("enabledPackages" to ids.reversed()) + ("enabledResources" to resources.reversed()))
        assertEquals(false, repo.status()["pending"])
        assertFalse(repo.hasActiveOrPending())
        val restored = GameModRepository(root)
        assertEquals(false, restored.status()["pending"])
        assertFalse(restored.hasActiveOrPending())
    }

    @Test fun `priority master and staged deletion remain pending changes`() {
        val repo = repository(); import(repo); import(repo)
        val ids = packages(repo).map { it["id"] as String }
        val resources = packages(repo).map { ((it["resources"] as List<*>).single() as Map<*, *>)["id"] as String }
        val config = mapOf("master" to true, "order" to ids, "enabledPackages" to ids, "enabledResources" to resources)
        repo.saveDraft(config); apply(repo)
        repo.saveDraft(config + ("order" to ids.reversed()))
        assertEquals(true, repo.status()["pending"])
        assertEquals(resources.last(), (repo.status()["winners"] as Map<*, *>)[target])
        assertEquals(resources.first(), (repo.status()["activeWinners"] as Map<*, *>)[target])
        repo.saveDraft(config + ("master" to false))
        assertEquals(true, repo.status()["pending"])
        repo.resetAll()
        val token = repo.applyDraft()
        assertEquals(repo.status()["draft"], repo.status()["applied"])
        assertEquals(true, repo.status()["pending"])
        assertTrue(repo.hasActiveOrPending())
        repo.finishApply(token)
        assertEquals(false, repo.status()["pending"])
        assertFalse(repo.hasActiveOrPending())
    }

    @Test fun `only expected official png GET requests can be overridden`() {
        val repo = repository(); import(repo); enable(repo); apply(repo)
        listOf("http://w01x.kancolle-server.com/$target", "https://evil.test/$target", "https://w01x.kancolle-server.com.evil.test/$target", "https://w01x.kancolle-server.com/$target?x=1", "https://w01x.kancolle-server.com/$target?version=1&x=2", "https://u@w01x.kancolle-server.com/$target", "https://w01x.kancolle-server.com:444/$target", "https://w01x.kancolle-server.com/kcs2/resources/ship/full/%2e%2e/0001_abcd.png").forEach { assertNull(it, repo.openResource(it, "GET", emptyMap())) }
        assertNull(repo.openResource(url, "POST", emptyMap()))
        assertNull(repo.openResource(url, "GET", mapOf("Range" to "bytes=0-2")))
        val response = repo.openResource(url, "GET", emptyMap())!!
        assertEquals("image/png", response.mimeType)
        assertEquals(200, response.statusCode)
        assertEquals(png().size.toString(), response.headers["Content-Length"])
        response.inputStream.close()
    }

    @Test fun `missing active file fails safely and records failure without loaded hit`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); enable(repo); apply(repo)
        root.walkTopDown().filter { it.isFile && it.extension == "png" }.forEach { it.delete() }
        assertNull(repo.openResource(url, "GET", emptyMap()))
        assertTrue((repo.status()["failures"] as Map<*, *>).containsKey(resourceId(repo)))
        assertEquals(emptyList<String>(), repo.status()["hits"])
    }

    @Test fun `unsupported resources cannot be enabled through malformed draft`() {
        val repo = repository()
        val preview = repo.preflight(zip("kcs2/sound/kc001/001.mp3", byteArrayOf(1, 2, 3)), "voice-cache.zip")
        assertEquals(0, preview["supportedCount"])
        repo.commitImport(preview["token"] as String)
        try { enable(repo); fail("unsupported resources must be rejected") } catch (e: GameModException) { assertEquals("invalid_config", e.code) }
    }

    @Test fun `truncated stream records failure and disables future override for session`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); enable(repo); apply(repo)
        val response = repo.openResource(url, "GET", emptyMap())!!
        val payload = root.walkTopDown().first { it.isFile && it.extension == "png" }
        java.io.RandomAccessFile(payload, "rw").use { it.setLength(1) }
        try { response.inputStream.use { it.readBytes() }; fail("truncation must surface") } catch (_: java.io.IOException) {}
        assertEquals(emptyList<String>(), repo.status()["hits"])
        assertNull(repo.openResource(url, "GET", emptyMap()))
        assertTrue((repo.status()["failures"] as Map<*, *>).containsKey(resourceId(repo)))
    }

    @Test fun `invalid draft never changes durable previous draft`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo)
        val previous = repo.status()["draft"]
        val invalid = listOf(
            mapOf("master" to "yes"),
            mapOf("master" to true, "order" to listOf("../../outside"), "enabledPackages" to emptyList<String>(), "enabledResources" to emptyList<String>()),
            config(repo) + ("enabledResources" to listOf("missing")),
            config(repo) + ("order" to listOf(packageId(repo), packageId(repo))),
        )
        invalid.forEach { value ->
            try { repo.saveDraft(value); fail("invalid draft accepted") } catch (e: GameModException) { assertEquals("invalid_config", e.code) }
            assertEquals(previous, repo.status()["draft"])
        }
        assertEquals(previous, GameModRepository(root).status()["draft"])
    }

    @Test fun `deletion waits for the last open response stream`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); enable(repo); apply(repo)
        val first = repo.openResource(url, "GET", emptyMap())!!
        val second = repo.openResource(url, "GET", emptyMap())!!
        val payload = root.walkTopDown().first { it.isFile && it.extension == "png" }
        repo.resetAll(); apply(repo)
        assertTrue(payload.exists())
        first.inputStream.close()
        assertTrue(payload.exists())
        second.inputStream.close()
        assertFalse(payload.exists())
    }

    @Test fun `staged deletion survives restart without disabling current applied session`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); enable(repo); apply(repo); repo.removePackage(packageId(repo))
        val restored = GameModRepository(root)
        assertNotNull(restored.openResource(url, "GET", emptyMap()).also { it?.inputStream?.close() })
        assertTrue(packages(restored).single()["pendingRemoval"] as Boolean)
        apply(restored)
        assertTrue(packages(restored).isEmpty())
        assertNull(GameModRepository(root).openResource(url, "GET", emptyMap()))
    }

    @Test fun `skipped bytes cannot produce a loaded status`() {
        val repo = repository(); import(repo); enable(repo); apply(repo)
        repo.openResource(url, "GET", emptyMap())!!.inputStream.use { it.skip(1); it.readBytes() }
        assertEquals(emptyList<String>(), repo.status()["hits"])
    }

    @Test fun `malformed durable index fails closed without clearing files outside mod root`() {
        val root = temporary.newFolder(); val marker = root.parentFile!!.resolve("keep-cache").apply { writeText("keep") }
        root.resolve("state.json").writeText("{broken")
        try { GameModRepository(root); fail("malformed index") } catch (e: GameModException) { assertEquals("storage_error", e.code) }
        assertEquals("keep", marker.readText())
    }

    @Test fun `real official server suffixes and single digit numbers are accepted`() {
        val repo = repository(); import(repo); enable(repo); apply(repo)
        listOf("w00g", "w15p", "w1a").forEach { host ->
            val response = repo.openResource("https://$host.kancolle-server.com/$target", "GET", emptyMap())
            assertNotNull(host, response)
            response!!.inputStream.close()
        }
    }

    @Test fun `a later read failure preserves a previously completed response hit`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); enable(repo); apply(repo)
        repo.openResource(url, "GET", emptyMap())!!.inputStream.use { it.readBytes() }
        root.walkTopDown().first { it.isFile && it.extension == "png" }.delete()
        assertNull(repo.openResource(url, "GET", emptyMap()))
        assertEquals(listOf(resourceId(repo)), repo.status()["hits"])
        assertTrue((repo.status()["failures"] as Map<*, *>).containsKey(resourceId(repo)))
    }

    @Test fun `import preselects supported resources while leaving package and master disabled`() {
        val repo = repository(); import(repo)
        val draft = repo.status()["draft"] as Map<*, *>
        assertEquals(false, draft["master"])
        assertEquals(emptyList<String>(), draft["enabledPackages"])
        assertEquals(listOf(resourceId(repo)), draft["enabledResources"])
        repo.saveDraft(draft + mapOf("master" to true, "enabledPackages" to listOf(packageId(repo))))
        apply(repo)
        assertNotNull(repo.openResource(url, "GET", emptyMap()).also { it?.inputStream?.close() })
    }

    @Test fun `preparation preserves active and durable state until publication`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); enable(repo); apply(repo)
        repo.resetAll()
        val before = root.resolve("state.json").readText()
        val token = repo.prepareApply()
        assertNotNull(repo.openResource(url, "GET", emptyMap()).also { it?.inputStream?.close() })
        assertEquals(before, root.resolve("state.json").readText())
        repo.publishApply(token)
        assertNull(repo.openResource(url, "GET", emptyMap()))
        repo.finishApply(token)
        assertTrue(packages(repo).isEmpty())
    }

    @Test fun `cancelled preparation leaves current session and pending draft intact`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); enable(repo); apply(repo); repo.resetAll()
        val before = root.resolve("state.json").readText()
        val session = repo.status()["sessionId"]
        val token = repo.prepareApply()
        assertEquals(session, repo.status()["sessionId"])
        repo.cancelPreparedApply(token)
        assertEquals(before, root.resolve("state.json").readText())
        assertEquals(true, repo.status()["pending"])
        assertNotNull(repo.openResource(url, "GET", emptyMap()).also { it?.inputStream?.close() })
        apply(repo)
        assertNull(repo.openResource(url, "GET", emptyMap()))
    }

    @Test fun `cleanup persistence failure keeps published state and allows later retry`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); enable(repo); apply(repo); repo.resetAll()
        val token = repo.applyDraft()
        val index = root.resolve("state.json")
        assertTrue(index.delete()); assertTrue(index.mkdir())
        try { repo.finishApply(token); fail("persistence failure") } catch (e: GameModException) { assertEquals("storage_error", e.code) }
        assertNull(repo.openResource(url, "GET", emptyMap()))
        assertEquals(true, repo.status()["pending"])
        assertTrue(index.delete())
        repo.saveDraft(repo.status()["draft"] as Map<*, *>)
        apply(repo)
        assertTrue(packages(repo).isEmpty())
    }

    @Test fun `an already open successful response records its hit after another request fails`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); enable(repo); apply(repo)
        val inFlight = repo.openResource(url, "GET", emptyMap())!!
        val payload = root.walkTopDown().first { it.isFile && it.extension == "png" }
        val valid = payload.readBytes()
        payload.writeBytes(byteArrayOf(0))
        assertNull(repo.openResource(url, "GET", emptyMap()))
        payload.writeBytes(valid)
        assertArrayEquals(valid, inFlight.inputStream.use { it.readBytes() })
        assertEquals(listOf(resourceId(repo)), repo.status()["hits"])
        assertTrue((repo.status()["failures"] as Map<*, *>).containsKey(resourceId(repo)))
    }

    @Test fun `discarded preflight cannot import and reset only deletes mod data`() {
        val root = temporary.newFolder(); val sibling = root.parentFile.resolve("outside-cache-marker").apply { writeText("keep") }
        val repo = GameModRepository(root)
        val preview = repo.preflight(zip(target), "cache.zip")
        repo.discardImport(preview["token"] as String)
        try { repo.commitImport(preview["token"] as String); fail("discarded token") } catch (e: GameModException) { assertEquals("invalid_token", e.code) }
        import(repo); enable(repo); apply(repo); repo.resetAll()
        assertTrue(repo.hasActiveOrPending())
        apply(repo)
        assertTrue(packages(repo).isEmpty())
        assertFalse(repo.hasActiveOrPending())
        assertEquals("keep", sibling.readText())
    }

    private fun repository() = GameModRepository(temporary.newFolder())
    private fun import(repo: GameModRepository) { val p = repo.preflight(zip(target), "cache.zip"); repo.commitImport(p["token"] as String) }
    private fun enable(repo: GameModRepository) = repo.saveDraft(config(repo))
    private fun apply(repo: GameModRepository) { repo.finishApply(repo.applyDraft()) }
    @Suppress("UNCHECKED_CAST") private fun packages(repo: GameModRepository) = repo.status()["packages"] as List<Map<String, Any?>>
    private fun packageId(repo: GameModRepository) = packages(repo).first()["id"] as String
    private fun resourceId(repo: GameModRepository) = ((packages(repo).first()["resources"] as List<*>).first() as Map<*, *>)["id"] as String
    private fun config(repo: GameModRepository, master: Boolean = true) = mapOf("master" to master, "order" to listOf(packageId(repo)), "enabledPackages" to listOf(packageId(repo)), "enabledResources" to listOf(resourceId(repo)))
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
    private fun zip(path: String, bytes: ByteArray = png()) = ByteArrayOutputStream().also { out -> ZipOutputStream(out).use { it.putNextEntry(ZipEntry("cache/$path")); it.write(bytes); it.closeEntry() } }.toByteArray().inputStream()
}
