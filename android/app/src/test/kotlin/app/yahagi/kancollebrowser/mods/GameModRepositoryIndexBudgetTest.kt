package app.yahagi.kancollebrowser.mods

import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Base64
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class GameModRepositoryIndexBudgetTest {
    @get:Rule val temporary = TemporaryFolder()
    private val path = "kcs2/img/index-budget.png"
    private val url = "https://w01x.kancolle-server.com/$path"
    private val png = Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg==")

    @Test fun `oversized import preserves the saved index active resources and cold startup`() {
        val root = temporary.newFolder("repository")
        val repository = GameModRepository(root)
        seedApplied(repository)
        val index = File(root, "state.json")
        val before = index.readBytes()
        val session = repository.portraitSnapshot()["token"]
        val inventory = repository.status()["packages"]
        val archive = longPathArchive(15)
        val preview = archive.inputStream().use { repository.preflight(it, "long-paths.zip") }
        assertEquals(8001, preview["resourceCount"])

        val failure = runCatching { repository.commitImport(preview["token"] as String) }.exceptionOrNull()

        assertEquals("An import must fail before publishing an unreadable index", "quota_exceeded", (failure as? GameModException)?.code)
        assertArrayEquals(before, index.readBytes())
        assertEquals(inventory, repository.status()["packages"])
        assertEquals(session, repository.portraitSnapshot()["token"])
        assertArrayEquals(png, repository.openResource(url, "GET", emptyMap())!!.inputStream.use { it.readBytes() })
        assertTrue(root.listFiles()!!.none { it.name.startsWith("state-") && it.name.endsWith(".tmp") })
        repository.discardImport(preview["token"] as String)
        assertTrue(File(root, "staging").listFiles()!!.isEmpty())
        val restarted = GameModRepository(root)
        assertEquals(inventory, restarted.status()["packages"])
        assertArrayEquals(png, restarted.openResource(url, "GET", emptyMap())!!.inputStream.use { it.readBytes() })
    }

    @Test fun `oversized prepared apply releases its reservation and preserves the applied session`() {
        val root = temporary.newFolder("repository")
        val repository = GameModRepository(root)
        seedApplied(repository)
        val archive = longPathArchive(8)
        val preview = archive.inputStream().use { repository.preflight(it, "large-draft.zip") }
        repository.commitImport(preview["token"] as String)
        val index = File(root, "state.json")
        assertTrue(index.length() < 64L * 1024 * 1024)
        val before = index.readBytes()
        val session = repository.portraitSnapshot()["token"]
        val applied = repository.exportAppliedConfiguration()

        val failure = runCatching { repository.prepareApply() }.exceptionOrNull()

        assertEquals("Duplicating the draft inventory into applied metadata must respect the same budget", "quota_exceeded", (failure as? GameModException)?.code)
        assertArrayEquals(before, index.readBytes())
        assertEquals(applied, repository.exportAppliedConfiguration())
        assertEquals(session, repository.portraitSnapshot()["token"])
        assertArrayEquals(png, repository.openResource(url, "GET", emptyMap())!!.inputStream.use { it.readBytes() })
        assertTrue(root.listFiles()!!.none { it.name.startsWith("state-") && it.name.endsWith(".tmp") })
        // A rejected preparation must not leave the mutation reservation held.
        repository.cancelChanges()
        assertEquals(applied, repository.exportAppliedConfiguration())
        val restarted = GameModRepository(root)
        assertEquals(applied, restarted.exportAppliedConfiguration())
        assertArrayEquals(png, restarted.openResource(url, "GET", emptyMap())!!.inputStream.use { it.readBytes() })
    }

    private fun seedApplied(repository: GameModRepository) {
        val archive = ByteArrayOutputStream().also { output ->
            ZipOutputStream(output).use { zip ->
                zip.putNextEntry(ZipEntry(path)); zip.write(png); zip.closeEntry()
            }
        }.toByteArray()
        val preview = repository.preflight(archive.inputStream(), "existing.zip")
        val pack = repository.commitImport(preview["token"] as String)
        val resource = (pack["resources"] as List<*>).single() as Map<*, *>
        repository.saveDraft(mapOf("master" to true, "order" to listOf(pack["id"]),
            "enabledPackages" to listOf(pack["id"]), "enabledResources" to listOf(resource["id"])))
        repository.finishApply(repository.applyDraft())
    }

    private fun longPathArchive(segments: Int): File {
        val archive = temporary.newFile("long-$segments.zip")
        val prefix = (1..segments).joinToString("/") { "a".repeat(190) }
        ZipOutputStream(archive.outputStream().buffered()).use { zip ->
            zip.putNextEntry(ZipEntry("kcs2/img/large-draft.png")); zip.write(png); zip.closeEntry()
            repeat(8000) { index ->
                zip.putNextEntry(ZipEntry("notes/$prefix/$index.txt")); zip.write(1); zip.closeEntry()
            }
        }
        assertTrue(archive.length() < 256L * 1024 * 1024)
        return archive
    }
}
