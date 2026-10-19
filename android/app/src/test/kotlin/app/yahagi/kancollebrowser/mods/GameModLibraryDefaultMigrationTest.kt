package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Test

class GameModLibraryDefaultMigrationTest {
    private val authority = "com.android.externalstorage.documents"
    private val old = "primary:Documents/Yahagi/魔改"
    private val target = "primary:Documents/Yahagi/Mods"

    @Test fun `exact legacy default is renamed once and saved without touching its contents`() {
        val access = Access(old)
        val bytes = access.contents.getValue(old)
        val result = migrate(access)
        assertEquals(target, result.rootDocumentId); assertNull(result.warning)
        assertSame(bytes, access.contents[target]); assertFalse(access.contents.containsKey(old))
        assertEquals(listOf("intent:$target", "rename:$old:Mods", "save:$target"), access.events)
    }
    @Test fun `a preexisting Mods directory is never overwritten or merged`() {
        val access = Access(old, target)
        val before = access.contents.toMap()
        val result = migrate(access)
        assertEquals(old, result.rootDocumentId)
        assertEquals("library_default_migration_conflict", result.warning)
        assertEquals(before, access.contents); assertTrue(access.events.isEmpty())
    }
    @Test fun `direct subtree grant keeps old directory usable without a rename`() {
        val access = Access(old)
        val result = GameModLibraryDefaultMigration.migrate(authority, old, false, null, access)
        assertEquals(old, result.rootDocumentId)
        assertEquals("library_default_migration_permission", result.warning)
        assertTrue(access.contents.containsKey(old)); assertTrue(access.events.isEmpty())
    }
    @Test fun `custom directories are preserved even when their final name is Chinese`() {
        for (root in listOf("primary:Documents/My Mods", "primary:Documents/Custom/魔改", "primary:Documents/Yahagi/Mods")) {
            val access = Access(root)
            val result = GameModLibraryDefaultMigration.migrate(authority, root, true, null, access)
            assertEquals(root, result.rootDocumentId); assertNull(result.warning); assertTrue(access.events.isEmpty())
        }
    }
    @Test fun `unsupported rename preserves source and clears prepared receipt`() {
        val access = Access(old).apply { renameFails = true }
        val result = migrate(access)
        assertEquals(old, result.rootDocumentId); assertEquals("library_default_migration_failed", result.warning)
        assertTrue(access.contents.containsKey(old)); assertNull(access.pending)
    }
    @Test fun `failed preference commit rolls the provider rename back`() {
        val access = Access(old).apply { saveFails = true }
        val result = migrate(access)
        assertEquals(old, result.rootDocumentId); assertEquals("library_default_migration_failed", result.warning)
        assertTrue(access.contents.containsKey(old)); assertFalse(access.contents.containsKey(target)); assertNull(access.pending)
    }
    @Test fun `a private receipt recovers a crash between provider rename and preference commit`() {
        val access = Access(target).apply { pending = target }
        val result = GameModLibraryDefaultMigration.migrate(authority, old, true, target, access)
        assertEquals(target, result.rootDocumentId); assertNull(result.warning)
        assertEquals(listOf("save:$target"), access.events); assertNull(access.pending)
    }
    @Test fun `an unrelated target without a receipt is never silently adopted`() {
        val access = Access(target)
        val result = migrate(access)
        assertEquals(old, result.rootDocumentId); assertEquals("library_default_migration_failed", result.warning)
        assertTrue(access.events.isEmpty())
    }
    @Test fun `failure to durably prepare prevents any provider rename`() {
        val access = Access(old).apply { intentFails = true }
        val result = migrate(access)
        assertEquals(old, result.rootDocumentId); assertEquals("library_default_migration_failed", result.warning)
        assertTrue(access.contents.containsKey(old)); assertFalse(access.events.any { it.startsWith("rename:") })
    }

    private fun migrate(access: Access) = GameModLibraryDefaultMigration.migrate(authority, old, true, null, access)
    private class Access(vararg paths: String) : GameModDefaultMigrationAccess {
        val contents = paths.associateWith { mutableMapOf(".yahagi-package.json" to "marker", "library.json" to "configuration", "resource.png" to "bytes") }.toMutableMap()
        val events = mutableListOf<String>()
        var pending: String? = null
        var renameFails = false
        var saveFails = false
        var intentFails = false
        override fun exists(documentId: String) = contents.containsKey(documentId)
        override fun rename(documentId: String, name: String): String? {
            events.add("rename:$documentId:$name")
            if (renameFails) return null
            val newId = documentId.substringBeforeLast('/') + "/$name"
            if (contents.containsKey(newId)) return null
            contents[newId] = contents.remove(documentId) ?: return null
            return newId
        }
        override fun recordIntent(targetId: String): Boolean {
            events.add("intent:$targetId"); if (intentFails) return false
            pending = targetId; return true
        }
        override fun saveRoot(targetId: String): Boolean {
            events.add("save:$targetId"); if (saveFails) return false
            pending = null; return true
        }
        override fun clearIntent() { pending = null }
    }
}
