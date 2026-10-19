package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Software portraits must observe applied winners without pretending a game request happened. */
class GameModPortraitTest {
    @get:Rule val temporary = TemporaryFolder()
    private val path = "kcs2/resources/ship/full/0001_abcd.png"

    @Test fun `snapshots are stable and ignore unpublished drafts`() {
        val repo = repository()
        val empty = snapshot(repo)
        assertTrue((empty["token"] as String).isNotEmpty())
        assertEquals(emptyList<Any>(), empty["resources"])
        import(repo); repo.saveDraft(config(repo))
        assertEquals(empty, snapshot(repo))
        val prepared = repo.prepareApply()
        assertEquals(empty, snapshot(repo))
        repo.cancelPreparedApply(prepared)
        assertEquals(empty, snapshot(repo))
        apply(repo)
        assertNotEquals(empty["token"], snapshot(repo)["token"])
        assertEquals(listOf(mapOf("id" to resourceIds(repo).single(), "path" to path)), snapshot(repo)["resources"])
        assertEquals(snapshot(repo), snapshot(repo))
    }

    @Test fun `snapshot includes active supported png only and portrait reads leave counters unchanged`() {
        val repo = repository()
        import(repo, mapOf(path to png(), "kcs2/img/common/test.png" to png(9),
            "kcs/resources/swf/ships/abcd.config.ini" to "[graph]\nboko_n_left=1\nboko_n_top=2\n".toByteArray(),
            "notes.txt" to "ignored".toByteArray()))
        repo.saveDraft(config(repo)); apply(repo)
        val before = repo.status()
        val snapshot = snapshot(repo)
        val images = images(snapshot)
        assertEquals(setOf(path, "kcs2/img/common/test.png"), images.map { it["path"] }.toSet())
        images.forEach { assertNotNull(read(repo, snapshot, it["id"] as String)) }
        assertEquals(before, repo.status())
        assertNull(read(repo, snapshot, resourceIds(repo).last()))
        assertEquals(before, repo.status())
    }

    @Test fun `tokens expire on publication and rollback restores previous token and bytes`() {
        val repo = repository(); import(repo); repo.saveDraft(config(repo)); apply(repo)
        val first = snapshot(repo); val id = images(first).single()["id"] as String
        assertArrayEquals(png(), read(repo, first, id))
        repo.saveDraft(config(repo, master = false))
        val token = repo.applyDraft()
        val disabled = snapshot(repo)
        assertNotEquals(first["token"], disabled["token"])
        assertEquals(emptyList<Any>(), disabled["resources"])
        assertNull(read(repo, first, id))
        repo.rollbackApply(token)
        assertEquals(first, snapshot(repo))
        assertArrayEquals(png(), read(repo, first, id))
        assertNull(read(repo, disabled, id))
    }

    @Test fun `package order and individual selection use the same applied winner as game`() {
        val repo = repository(); import(repo); import(repo, mapOf(path to png(2)))
        val ids = packageIds(repo); val resources = resourceIds(repo)
        repo.saveDraft(config(repo)); apply(repo)
        assertImage(repo, resources.first(), png())
        repo.saveDraft(config(repo) + ("order" to ids.reversed()))
        assertImage(repo, resources.first(), png())
        apply(repo); assertImage(repo, resources.last(), png(2))
        repo.saveDraft(config(repo) + ("order" to ids.reversed()) + ("enabledResources" to resources.take(1)))
        apply(repo); assertImage(repo, resources.first(), png())
        assertEquals(resources.first(), (repo.status()["activeWinners"] as Map<*, *>)[path])
    }

    @Test fun `master package and resource toggles repeatedly preserve originals until applied`() {
        val repo = repository(); import(repo); repo.saveDraft(config(repo)); apply(repo)
        val id = resourceIds(repo).single()
        repeat(3) {
            listOf(mapOf("master" to false), mapOf("enabledPackages" to emptyList<String>()),
                mapOf("enabledResources" to emptyList<String>())).forEach { off ->
                val previous = snapshot(repo)
                repo.saveDraft(config(repo) + off)
                assertEquals(previous, snapshot(repo)); assertImage(repo, id, png())
                apply(repo)
                assertEquals(emptyList<Any>(), snapshot(repo)["resources"])
                assertNull(read(repo, previous, id))
                repo.saveDraft(config(repo)); apply(repo); assertImage(repo, id, png())
            }
        }
        assertEquals(emptyList<Any>(), repo.status()["hits"])
        assertEquals(emptyMap<String, Any>(), repo.status()["failures"])
    }

    @Test fun `staged delete and reset keep active portraits and delete only after application`() {
        repeat(3) { round ->
            val root = temporary.newFolder("removal-$round"); val repo = GameModRepository(root)
            import(repo); import(repo, mapOf(path to png(2))); repo.saveDraft(config(repo)); apply(repo)
            val first = snapshot(repo); val firstId = images(first).single()["id"] as String
            val ownedBytes = read(repo, first, firstId)!!
            repo.removePackage(packageIds(repo).first())
            assertEquals(first, snapshot(repo)); assertArrayEquals(png(), read(repo, first, firstId))
            apply(repo)
            assertNull(read(repo, first, firstId)); assertImage(repo, resourceIds(repo).single(), png(2))
            assertArrayEquals(png(), ownedBytes)
            val second = snapshot(repo)
            repo.resetAll(); assertEquals(second, snapshot(repo))
            apply(repo)
            assertEquals(emptyList<Any>(), snapshot(repo)["resources"])
            assertEquals(emptyList<Any>(), repo.status()["packages"])
            assertTrue(root.resolve("packages").listFiles()!!.isEmpty())
            assertArrayEquals(png(), ownedBytes)
        }
    }

    @Test fun `unknown token resource and nonwinning resource return null without counters`() {
        val repo = repository(); import(repo); import(repo); repo.saveDraft(config(repo)); apply(repo)
        val before = repo.status(); val current = snapshot(repo)
        assertNull(read(repo, current + ("token" to "expired"), resourceIds(repo).first()))
        assertNull(read(repo, current, "../../outside"))
        assertNull(read(repo, current, resourceIds(repo).last()))
        assertEquals(before, repo.status())
    }

    @Test fun `missing changed and crc damaged private pngs fail without poisoning game state`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); repo.saveDraft(config(repo)); apply(repo)
        val current = snapshot(repo); val id = resourceIds(repo).single()
        val file = root.walkTopDown().single { it.isFile && it.extension == "png" }
        val original = file.readBytes(); val before = repo.status()
        file.writeBytes(original.copyOf(original.size - 1)); assertNull(read(repo, current, id))
        file.writeBytes(original.clone().also { it[it.size - 5] = 1 }); assertNull(read(repo, current, id))
        file.writeBytes(original); assertArrayEquals(original, read(repo, current, id))
        file.delete(); assertNull(read(repo, current, id))
        assertEquals(before, repo.status())
    }

    @Test fun `reads remain available after independent game failures without clearing their diagnostics`() {
        val root = temporary.newFolder(); val repo = GameModRepository(root)
        import(repo); repo.saveDraft(config(repo)); apply(repo)
        val file = root.walkTopDown().single { it.isFile && it.extension == "png" }
        val original = file.readBytes(); file.writeBytes(byteArrayOf(0))
        assertNull(repo.openResource("https://w01x.kancolle-server.com/$path", "GET", emptyMap()))
        file.writeBytes(original)
        val before = repo.status(); val current = snapshot(repo)
        assertArrayEquals(original, read(repo, current, images(current).single()["id"] as String))
        assertEquals(before, repo.status())
    }

    private fun assertImage(repo: GameModRepository, id: String, bytes: ByteArray) {
        val current = snapshot(repo)
        assertEquals(listOf(mapOf("id" to id, "path" to path)), current["resources"])
        assertArrayEquals(bytes, read(repo, current, id))
    }
    private fun snapshot(repo: GameModRepository): Map<String, Any?> = repo.portraitSnapshot()
    private fun read(repo: GameModRepository, snapshot: Map<String, Any?>, id: String): ByteArray? =
        repo.readPortrait(snapshot["token"] as String, id)
    @Suppress("UNCHECKED_CAST") private fun images(snapshot: Map<String, Any?>) = snapshot["resources"] as List<Map<String, Any?>>
    private fun repository() = GameModRepository(temporary.newFolder())
    private fun packageIds(repo: GameModRepository) = (repo.status()["packages"] as List<*>).map { (it as Map<*, *>)["id"] as String }
    private fun resourceIds(repo: GameModRepository) = (repo.status()["packages"] as List<*>).flatMap {
        ((it as Map<*, *>)["resources"] as List<*>).filter { (it as Map<*, *>)["supported"] == true }
            .map { (it as Map<*, *>)["id"] as String }
    }
    private fun config(repo: GameModRepository, master: Boolean = true) = mapOf("master" to master,
        "order" to packageIds(repo), "enabledPackages" to packageIds(repo), "enabledResources" to resourceIds(repo))
    private fun apply(repo: GameModRepository) = repo.finishApply(repo.applyDraft())
    private fun import(repo: GameModRepository, contents: Map<String, ByteArray> = mapOf(path to png())) {
        val bytes = ByteArrayOutputStream().also { out -> ZipOutputStream(out).use { zip -> contents.forEach { (name, data) ->
            zip.putNextEntry(ZipEntry("cache/$name")); zip.write(data); zip.closeEntry()
        } } }.toByteArray()
        repo.commitImport(repo.preflight(bytes.inputStream(), "cache.zip")["token"] as String)
    }
    private fun png(red: Int = 1): ByteArray = ByteArrayOutputStream().also { out ->
        val data = DataOutputStream(out); data.write(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
        fun chunk(type: String, bytes: ByteArray) {
            val kind = type.toByteArray(Charsets.US_ASCII)
            data.writeInt(bytes.size); data.write(kind); data.write(bytes)
            data.writeInt(CRC32().apply { update(kind); update(bytes) }.value.toInt())
        }
        val header = ByteArrayOutputStream().also { DataOutputStream(it).apply { writeInt(1); writeInt(1); write(byteArrayOf(8, 6, 0, 0, 0)) } }.toByteArray()
        val compressed = ByteArrayOutputStream().also { DeflaterOutputStream(it).use { it.write(byteArrayOf(0, red.toByte(), 0, 0, -1)) } }.toByteArray()
        chunk("IHDR", header); chunk("IDAT", compressed); chunk("IEND", byteArrayOf())
    }.toByteArray()
}
