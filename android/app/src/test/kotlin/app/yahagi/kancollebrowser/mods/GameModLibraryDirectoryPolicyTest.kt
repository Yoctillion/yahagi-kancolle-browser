package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Test
import java.lang.reflect.InvocationTargetException

class GameModLibraryDirectoryPolicyTest {
    @Test fun `Documents root becomes dedicated Yahagi library instead of scanning all documents`() {
        assertEquals("primary:Documents/Yahagi/Mods", selection("com.android.externalstorage.documents", "primary:Documents"))
    }
    @Test fun `existing document subfolder and removable volume preserve selected directory`() {
        assertEquals("primary:Documents/My Mods", selection("com.android.externalstorage.documents", "primary:Documents/My Mods"))
        assertEquals("1234-ABCD:Documents/Mods", selection("com.android.externalstorage.documents", "1234-ABCD:Documents/Mods"))
    }
    @Test fun `same library has stable identity through Documents grant or direct folder grant`() {
        val authority = "com.android.externalstorage.documents"
        val fromDocumentsGrant = selection(authority, "primary:Documents")
        val fromDirectGrant = selection(authority, "primary:Documents/Yahagi/魔改")
        assertEquals(stableIdentity(authority, fromDocumentsGrant), stableIdentity(authority, fromDirectGrant))
        assertNotEquals(stableIdentity(authority, fromDirectGrant), stableIdentity(authority, "primary:Documents/Other Mods"))
        assertNotEquals(stableIdentity(authority, fromDirectGrant), stableIdentity(authority, "1234-ABCD:Documents/Yahagi/魔改"))
    }
    @Test fun `selection rejects nonlocal and private Android directories`() {
        for ((authority, id) in listOf("cloud.example" to "primary:Documents/Mods", "com.android.externalstorage.documents" to "primary:Android/data", "com.android.externalstorage.documents" to "primary:")) {
            expectFailure { selection(authority, id) }
        }
    }
    @Test fun `English default keeps legacy library identity and pending synchronization workspace`() {
        val authority = "com.android.externalstorage.documents"
        assertEquals("$authority:primary:Documents/Yahagi/魔改", stableIdentity(authority, "primary:Documents/Yahagi/Mods"))
        assertEquals(stableIdentity(authority, "primary:Documents/Yahagi/魔改"), stableIdentity(authority, "primary:Documents/Yahagi/Mods"))
        assertNotEquals(stableIdentity(authority, "primary:Documents/My Mods"), stableIdentity(authority, "primary:Documents/Yahagi/Mods"))
    }
    @Test fun `relative operations reject root deletion traversal and ambiguous separators`() {
        for (path in listOf("", "/outside", "../outside", "a/../b", "a//b", "a\\b", "a:b", "a/./b", "a\u0000b")) expectFailure { relative(path, false) }
        assertEquals("", relative("", true))
        assertEquals("吹雪/kcs2/img/01.png", relative("吹雪/kcs2/img/01.png", false))
    }
    private fun selection(authority: String, id: String): String = invoke("selectDocumentId", arrayOf(authority, id), arrayOf(String::class.java, String::class.java))
    private fun relative(value: String, allowRoot: Boolean): String = invoke("relativePath", arrayOf(value, allowRoot), arrayOf(String::class.java, Boolean::class.javaPrimitiveType!!))
    private fun stableIdentity(authority: String, root: String): String = try {
        invoke("libraryIdentity", arrayOf(authority, root), arrayOf(String::class.java, String::class.java))
    } catch (error: NoSuchMethodException) { throw AssertionError("Missing stable identity for a public library independent of its tree grant", error) }
    private fun invoke(method: String, values: Array<Any>, types: Array<Class<*>>): String {
        val cls = try { Class.forName("app.yahagi.kancollebrowser.mods.GameModLibraryDirectoryPolicy") }
        catch (_: ClassNotFoundException) { throw AssertionError("Missing library directory policy") }
        try { return cls.getMethod(method, *types).invoke(cls.getField("INSTANCE").get(null), *values) as String }
        catch (error: InvocationTargetException) { throw error.targetException }
    }
    private fun expectFailure(block: () -> Unit) {
        try { block(); fail("Unsafe location accepted") } catch (expected: GameModException) { assertTrue(expected.code in setOf("library_directory_required", "unsafe_path")) }
    }
}
