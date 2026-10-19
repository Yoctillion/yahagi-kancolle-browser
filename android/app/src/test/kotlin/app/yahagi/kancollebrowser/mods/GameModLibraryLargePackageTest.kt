package app.yahagi.kancollebrowser.mods

import java.io.File
import java.util.Random
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class GameModLibraryLargePackageTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun `legal compressed ZIP expanded above 256 MiB survives library migration and fresh private restore`() {
        val tree = temporary.newFolder("tree")
        // Unsupported accompanying files are legal and must survive migration too.
        val block = ByteArray(64 * 1024)
        val random = Random(47)
        repeat(5) { index ->
            File(tree, "notes/large-$index.bin").apply {
                parentFile!!.mkdirs()
                outputStream().buffered().use { output -> repeat(880) {
                    random.nextBytes(block)
                    block.fill(0, block.size / 2)
                    output.write(block)
                } }
            }
        }
        val png = java.util.Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg==")
        File(tree, "kcs2/resources/ship/full/0001_1234_secret.png").apply { parentFile!!.mkdirs(); writeBytes(png) }
        val source = temporary.newFile("original.zip")
        ZipOutputStream(source.outputStream().buffered()).use { zip ->
            tree.walkTopDown().filter { it.isFile }.forEach { file ->
                zip.putNextEntry(ZipEntry(file.relativeTo(tree).invariantSeparatorsPath))
                file.inputStream().use { it.copyTo(zip) }; zip.closeEntry()
            }
        }
        assertTrue(source.length() < 256L * 1024 * 1024)
        val before = GameModRepository(temporary.newFolder("before"))
        val preview = source.inputStream().use { before.preflight(it, source.name) }
        val id = before.commitImport(preview["token"] as String)["id"] as String
        val public = temporary.newFolder("public")
        val library = GameModLibrary(GameModFileLibraryStore(public), temporary.newFolder("worker"))
        val coordinator = GameModLibraryCoordinator(before, library, temporary.newFolder("sync"))
        assertEquals(1, coordinator.migrateExisting())
        val scan = library.scan()
        val candidate = library.acceptScan(scan.token).single()
        assertTrue("Internal checked archives retain the 1 GiB expanded allowance", candidate.archive.length() > 256L * 1024 * 1024)
        val restored = GameModRepository(temporary.newFolder("restored"))
        val checked = candidate.archive.inputStream().use { restored.preflightLibrary(it, candidate.name) }
        restored.commitLibraryImport(checked["token"] as String, candidate.id, candidate.contentHash)
        assertEquals(id, (restored.status()["packages"] as List<*>).single().let { (it as Map<*, *>)["id"] })
        assertEquals(6, (checked["resourceCount"] as Number).toInt())
        val rejected = runCatching { candidate.archive.inputStream().use { restored.preflight(it, "external.zip") } }.exceptionOrNull()
        assertEquals("External ZIP input keeps its original 256 MiB limit", "quota_exceeded", (rejected as? GameModException)?.code)
        library.discardScan(scan.token)
    }
}
