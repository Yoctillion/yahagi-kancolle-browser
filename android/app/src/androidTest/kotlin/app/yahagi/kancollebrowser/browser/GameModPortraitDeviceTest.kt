package app.yahagi.kancollebrowser.browser

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.yahagi.kancollebrowser.mods.GameModRepository
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real installed packages, copied into isolated repositories before any mutation. */
@Suppress("UNCHECKED_CAST")
@RunWith(AndroidJUnit4::class)
class GameModPortraitDeviceTest {
    private fun entries(snapshot: Map<String, Any?>) = snapshot["resources"] as List<Map<String, Any?>>
    private fun token(snapshot: Map<String, Any?>) = snapshot["token"] as String
    private fun draft(repo: GameModRepository) = (repo.status()["draft"] as Map<String, Any?>).toMutableMap()
    private fun apply(repo: GameModRepository) = repo.finishApply(repo.applyDraft())
    private fun read(repo: GameModRepository, path: String): ByteArray {
        val snapshot = repo.portraitSnapshot()
        val resource = entries(snapshot).single { it["path"] == path }
        return requireNotNull(repo.readPortrait(token(snapshot), resource["id"] as String))
    }
    private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun paths(repo: GameModRepository) = entries(repo.portraitSnapshot()).map { it["path"] as String }.toSet()

    private fun isolated(block: (GameModRepository, File) -> Unit) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val original = File(context.filesDir, "mod_manager")
        val before = File(original, "state.json").readBytes()
        val root = File(context.cacheDir, "mod-portrait-device-${System.nanoTime()}")
        try {
            assertTrue(original.copyRecursively(File(root, "mods")))
            val cacheMarker = File(root, "ordinary-image-cache.png").apply { writeBytes(byteArrayOf(1, 2, 3)) }
            block(GameModRepository(File(root, "mods")), root)
            assertArrayEquals(byteArrayOf(1, 2, 3), cacheMarker.readBytes())
            assertArrayEquals("User mod configuration must remain untouched", before, File(original, "state.json").readBytes())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test fun realPngsDecodeAndRepeatedTogglesPreserveOriginalFallback() = isolated { repo, _ ->
        val baseline = draft(repo)
        val initial = paths(repo)
        assertEquals(3, (repo.status()["packages"] as List<*>).size)
        val targets = linkedMapOf(
            "kcs2/resources/ship/full/0607_4674_tciiyagxjjpu.png" to Pair(582, 984),
            "kcs2/resources/ship/banner/0735_8629.png" to Pair(240, 60),
            "kcs2/resources/ship/banner/0426_4278.png" to Pair(240, 60),
        )
        val expected = targets.mapValues { (path, size) ->
            val bytes = read(repo, path)
            val bitmap = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size))
            try {
                assertEquals(size.first, bitmap.width)
                assertEquals(size.second, bitmap.height)
            } finally { bitmap.recycle() }
            digest(bytes)
        }
        repeat(3) { cycle ->
            val old = repo.portraitSnapshot()
            repo.saveDraft(baseline + ("master" to false))
            assertEquals("Draft cannot change visible portraits", initial, paths(repo))
            apply(repo)
            assertTrue(paths(repo).isEmpty())
            val oldResource = entries(old).first()["id"] as String
            assertNull(repo.readPortrait(token(old), oldResource))
            repo.saveDraft(baseline)
            apply(repo)
            assertEquals(initial, paths(repo))

            targets.keys.forEach { target ->
                val snapshot = repo.portraitSnapshot()
                val entry = entries(snapshot).single { it["path"] == target }
                val resourceId = entry["id"] as String
                val resourceIds = baseline["enabledResources"] as List<String>
                repo.saveDraft(baseline + ("enabledResources" to resourceIds.filterNot { it == resourceId }))
                assertNotNull(repo.readPortrait(token(snapshot), resourceId))
                apply(repo)
                assertFalse(paths(repo).contains(target))
                repo.saveDraft(baseline)
                apply(repo)
                assertEquals(expected.getValue(target), digest(read(repo, target)))
            }
            (baseline["enabledPackages"] as List<String>).forEach { packageId ->
                repo.saveDraft(baseline + ("enabledPackages" to (baseline["enabledPackages"] as List<String>).filterNot { it == packageId }))
                apply(repo)
                val ids = entries(repo.portraitSnapshot()).map { it["id"] as String }
                assertTrue(ids.none { it.startsWith("$packageId:") })
                repo.saveDraft(baseline)
                apply(repo)
            }
            assertTrue((repo.status()["hits"] as List<*>).isEmpty())
            assertTrue((repo.status()["failures"] as Map<*, *>).isEmpty())
            Log.i("ModPortraitProbe", "three-package toggle cycle ${cycle + 1}: OK")
        }
        Log.i("ModPortraitProbe", "three PNG decode SHA256: $expected")
    }

    @Test fun priorityRollbackDeletionAndResetRestoreOtherPackageSources() {
        repeat(3) { cycle -> isolated { repo, _ ->
            val baseline = draft(repo)
            val baselinePaths = paths(repo)
            val target = "kcs2/resources/ship/banner/0426_4278.png"
            val original = read(repo, target)
            val replacement = ByteArrayOutputStream().use { bytes ->
                val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
                try { bitmap.eraseColor(Color.MAGENTA); bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes) }
                finally { bitmap.recycle() }
                bytes.toByteArray()
            }
            val zip = ByteArrayOutputStream().use { bytes ->
                ZipOutputStream(bytes).use { stream ->
                    stream.putNextEntry(ZipEntry(target)); stream.write(replacement); stream.closeEntry()
                }
                bytes.toByteArray()
            }
            val preflight = repo.preflight(ByteArrayInputStream(zip), "portrait-conflict.zip")
            val added = repo.commitImport(preflight["token"] as String)
            val id = added["id"] as String
            val conflict = draft(repo).apply {
                this["enabledPackages"] = (baseline["enabledPackages"] as List<String>) + id
                this["order"] = listOf(id) + (baseline["order"] as List<String>)
            }
            repo.saveDraft(conflict)
            apply(repo)
            assertArrayEquals(replacement, read(repo, target))

            repo.saveDraft(conflict + ("order" to (baseline["order"] as List<String>) + id))
            val transaction = repo.applyDraft()
            val temporary = repo.portraitSnapshot()
            assertArrayEquals(original, read(repo, target))
            repo.rollbackApply(transaction)
            assertArrayEquals(replacement, read(repo, target))
            val temporaryId = entries(temporary).single { it["path"] == target }["id"] as String
            assertNull(repo.readPortrait(token(temporary), temporaryId))

            repo.removePackage(id)
            assertArrayEquals(replacement, read(repo, target))
            apply(repo)
            assertArrayEquals(original, read(repo, target))
            assertEquals(baselinePaths, paths(repo))

            val removedId = (baseline["order"] as List<String>)[cycle]
            repo.removePackage(removedId)
            apply(repo)
            assertTrue(entries(repo.portraitSnapshot()).none { (it["id"] as String).startsWith("$removedId:") })
            assertEquals(2, (repo.status()["packages"] as List<*>).size)
            val beforeReset = repo.portraitSnapshot()
            repo.resetAll()
            assertTrue(entries(repo.portraitSnapshot()).isNotEmpty())
            apply(repo)
            assertTrue(entries(repo.portraitSnapshot()).isEmpty())
            assertTrue((repo.status()["packages"] as List<*>).isEmpty())
            val priorId = entries(beforeReset).first()["id"] as String
            assertNull(repo.readPortrait(token(beforeReset), priorId))
            assertTrue((repo.status()["hits"] as List<*>).isEmpty())
            assertTrue((repo.status()["failures"] as Map<*, *>).isEmpty())
            Log.i("ModPortraitProbe", "priority/rollback/delete/reset cycle ${cycle + 1}: OK")
        } }
    }
}
