package app.yahagi.kancollebrowser.nativewebview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class NativeGamePresentationQueryTest {
    @Test
    fun staleDocumentOrOlderQueryCannotChangeCurrentPresentation() {
        val query = NativeGamePresentationQuery()
        val oldDocument = query.begin(1)
        val currentDocument = query.begin(2)
        assertNull(query.resolve(oldDocument, 2, "\"game\""))
        assertEquals("pending", query.resolve(currentDocument, 2, "\"pending\""))
        val olderQuery = query.begin(2)
        val newestQuery = query.begin(2)
        assertNull(query.resolve(olderQuery, 2, "\"game\""))
        assertEquals("web", query.resolve(newestQuery, 2, "\"web\""))
    }

    @Test
    fun readsOnlyFixedCurrentStateWithoutCallingSyncOrBridge() {
        val query = NativeGamePresentationQuery()
        for (state in listOf("game", "pending", "web")) {
            val token = query.begin(1)
            assertEquals(state, query.resolve(token, 1, "\"$state\""))
        }
        for (invalid in listOf("null", "\"private URL\"", "false", "{}")) {
            assertNull(query.resolve(query.begin(1), 1, invalid))
        }
        assertFalse(NativeGamePresentationQuery.SCRIPT.contains("SyncPresentation"))
        assertFalse(NativeGamePresentationQuery.SCRIPT.contains("postMessage"))
    }
}
