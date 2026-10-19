package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.InputStream
import java.util.UUID
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class GameModRepositoryPerformanceTest {
    @get:Rule val temporary = TemporaryFolder()
    private val path = "kcs2/img/performance/ship.png"

    @Test fun `unchanged response and portrait closes defer orphan maintenance until a lifecycle checkpoint`() {
        val root = temporary.newFolder()
        val repo = GameModRepository(root)
        val id = UUID.randomUUID().toString()
        val preview = repo.preflight(archive(path, fixturePng()), "cache.zip")
        repo.commitLibraryImport(preview["token"] as String, id)
        @Suppress("UNCHECKED_CAST") val pack = (repo.status()["packages"] as List<Map<String, Any?>>).single()
        @Suppress("UNCHECKED_CAST") val resource = (pack["resources"] as List<Map<String, Any?>>).single()
        repo.saveDraft(mapOf("master" to true, "order" to listOf(id), "enabledPackages" to listOf(id),
            "enabledResources" to listOf(resource["id"])))
        repo.finishApply(repo.applyDraft())
        // A leftover private revision is only a maintenance concern. Merely displaying
        // unchanged images must not initiate a whole-library directory traversal.
        val orphan = root.resolve("packages/$id/revisions/unreferenced-checkpoint/file.txt")
        assertTrue(orphan.parentFile!!.mkdirs()); orphan.writeText("defer maintenance")
        val token = repo.portraitSnapshot()["token"] as String
        repeat(20) {
            val response = repo.openResource("https://w01x.kancolle-server.com/$path", "GET", emptyMap())!!
            assertArrayEquals(fixturePng(), response.inputStream.use { it.readBytes() })
            assertArrayEquals(fixturePng(), repo.readPortrait(token, resource["id"] as String))
        }
        assertTrue("Stable read/close operations must not run repository maintenance", orphan.exists())
        GameModRepository(root)
        assertFalse("Startup must still recover unreferenced private revisions", orphan.exists())
    }

    @Test fun `progress callback reports first actual byte once across many small reads`() {
        val callbacks = Callbacks()
        val bytes = ByteArray(257) { it.toByte() }
        val stream = tracked(ByteArrayInputStream(bytes), bytes.size.toLong(), callbacks)
        val actual = ByteArrayOutputStream()
        assertEquals(bytes[0].toInt() and 255, stream.read()); actual.write(bytes[0].toInt())
        val buffer = ByteArray(3)
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            actual.write(buffer, 0, count)
        }
        stream.close(); stream.close()
        assertArrayEquals(bytes, actual.toByteArray())
        assertEquals(1, callbacks.progress); assertEquals(1, callbacks.completed)
        assertEquals(1, callbacks.closed); assertEquals(0, callbacks.failures)
    }

    @Test fun `a protected old audio revision does not make other closes scan and does not block other deletion`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        val voiceId = UUID.randomUUID().toString(); val imageId = UUID.randomUUID().toString()
        val voiceSource = "kcs/sound/kcperformance/100.wav"
        val voiceTarget = voiceSource.dropLast(4) + ".mp3"
        fun import(id: String, name: String, bytes: ByteArray) {
            val preview = repo.preflight(archive(name, bytes), "cache.zip")
            repo.commitLibraryImport(preview["token"] as String, id)
        }
        import(voiceId, voiceSource, fixtureWav(20)); import(imageId, path, fixturePng())
        @Suppress("UNCHECKED_CAST") val packs = repo.status()["packages"] as List<Map<String, Any?>>
        val resources = packs.flatMap { (it["resources"] as List<*>).map { value -> (value as Map<*, *>)["id"] as String } }
        repo.saveDraft(mapOf("master" to true, "order" to listOf(voiceId, imageId),
            "enabledPackages" to listOf(voiceId, imageId), "enabledResources" to resources))
        repo.finishApply(repo.applyDraft())
        val oldRevision = root.resolve("packages/$voiceId/revisions").listFiles()!!.single()
        val oldStream = repo.openResource("https://w01x.kancolle-server.com/$voiceTarget", "GET", emptyMap())!!.inputStream
        try {
            import(voiceId, voiceSource, fixtureWav(30)); repo.finishApply(repo.applyDraft())
            assertTrue("An old voice stream must retain its immutable revision", oldRevision.exists())
            val orphan = root.resolve("packages/$imageId/revisions/unreferenced-checkpoint/file.txt")
            assertTrue(orphan.parentFile!!.mkdirs()); orphan.writeText("no unrelated scan")
            val portraitToken = repo.portraitSnapshot()["token"] as String
            val imageResource = (packs.single { it["id"] == imageId }["resources"] as List<*>).single() as Map<*, *>
            repeat(20) {
                repo.openResource("https://w01x.kancolle-server.com/$path", "GET", emptyMap())!!.inputStream.use { it.readBytes() }
                assertArrayEquals(fixturePng(), repo.readPortrait(portraitToken, imageResource["id"] as String))
            }
            assertTrue("Lease-protected work must not cause unrelated package scans", orphan.exists())
            repo.removePackage(imageId); repo.finishApply(repo.applyDraft())
            assertFalse("Another package's lease must not delay this deletion", root.resolve("packages/$imageId").exists())
            assertTrue(oldRevision.exists())
            assertArrayEquals(fixtureWav(20), oldStream.readBytes())
        } finally { oldStream.close() }
        assertFalse("The last old voice lease must reclaim the old revision", oldRevision.exists())
        val restarted = GameModRepository(root)
        assertArrayEquals(fixtureWav(30), restarted.openResource("https://w01x.kancolle-server.com/$voiceTarget", "GET", emptyMap())!!.inputStream.use { it.readBytes() })
    }

    @Test fun `early close and skips keep partial and completion semantics`() {
        val early = Callbacks()
        tracked(ByteArrayInputStream(ByteArray(20)), 20, early).use { it.read(); it.read(); it.read() }
        assertEquals(1, early.progress); assertEquals(0, early.completed); assertEquals(1, early.closed)
        val skipped = Callbacks()
        tracked(ByteArrayInputStream(ByteArray(20)), 20, skipped).use { assertEquals(20L, it.skip(20)); assertEquals(-1, it.read()) }
        assertEquals(0, skipped.progress); assertEquals(0, skipped.completed); assertEquals(1, skipped.closed)
        val mixed = Callbacks()
        tracked(ByteArrayInputStream(ByteArray(20)), 20, mixed).use { it.skip(5); while (it.read() != -1) { } }
        assertEquals(1, mixed.progress); assertEquals(0, mixed.completed); assertEquals(1, mixed.closed)
    }

    private data class Callbacks(var progress: Int = 0, var completed: Int = 0, var closed: Int = 0, var failures: Int = 0)
    private fun tracked(source: InputStream, size: Long, callbacks: Callbacks): InputStream {
        // Keep the production wrapper private; no diagnostic callback or public API is added.
        val constructor = Class.forName("app.yahagi.kancollebrowser.mods.CompletionStream").declaredConstructors.single()
        constructor.isAccessible = true
        return constructor.newInstance(source, size, { callbacks.completed++; Unit }, { callbacks.progress++; Unit },
            { _: String -> callbacks.failures++; Unit }, { callbacks.closed++; Unit }) as InputStream
    }

    private fun archive(path: String, bytes: ByteArray) = ByteArrayOutputStream().also { output ->
        ZipOutputStream(output).use { zip -> zip.putNextEntry(ZipEntry(path)); zip.write(bytes); zip.closeEntry() }
    }.toByteArray().inputStream()

    internal companion object {
        fun fixtureWav(sample: Int): ByteArray = ByteArrayOutputStream().also { output ->
            val data = DataOutputStream(output)
            fun little(value: Int, bytes: Int) { repeat(bytes) { data.writeByte(value ushr (8 * it)) } }
            data.writeBytes("RIFF"); little(38, 4); data.writeBytes("WAVEfmt "); little(16, 4)
            little(1, 2); little(1, 2); little(8000, 4); little(16000, 4); little(2, 2); little(16, 2)
            data.writeBytes("data"); little(2, 4); little(sample, 2)
        }.toByteArray()
        fun fixturePng(): ByteArray = ByteArrayOutputStream().also { output ->
            val data = DataOutputStream(output); data.write(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
            fun chunk(name: String, bytes: ByteArray) { val tag = name.toByteArray(); data.writeInt(bytes.size); data.write(tag); data.write(bytes); data.writeInt(CRC32().apply { update(tag); update(bytes) }.value.toInt()) }
            chunk("IHDR", ByteArrayOutputStream().also { DataOutputStream(it).apply { writeInt(1); writeInt(1); write(byteArrayOf(8, 6, 0, 0, 0)) } }.toByteArray())
            chunk("IDAT", ByteArrayOutputStream().also { DeflaterOutputStream(it).use { it.write(byteArrayOf(0, 20, 30, 40, -1)) } }.toByteArray())
            chunk("IEND", byteArrayOf())
        }.toByteArray()
    }
}
