package app.yahagi.kancollebrowser.browser

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GameFrameReloadBridgeTest {
    @Test
    fun platformViewDocumentsInstallCoordinateHookBeforeReloadScripts() {
        val scripts = platformGameDocumentStartScripts()
        val coordinates = scripts.first()
        assertTrue(coordinates.source.contains("/__yahagi_mods__/coordinates.json"))
        assertEquals(setOf("https://*.kancolle-server.com"), coordinates.allowedOriginRules)
        assertTrue(coordinates.source.contains("api_mst_shipgraph"))
    }

    @Test
    fun platformViewDocumentsDisableChromiumTapHighlightBeforeNavigation() {
        val scripts = platformGameDocumentStartScripts()

        val touchFeedback = scripts.single {
            it.source.contains("-webkit-tap-highlight-color")
        }
        assertTrue(touchFeedback.source.contains("transparent"))
        assertFalse(touchFeedback.source.contains("preventDefault"))
        assertEquals(
            setOf("https://*.kancolle-server.com"),
            touchFeedback.allowedOriginRules,
        )
    }

    @Test
    fun scriptReloadsOnlyHtmlWrapAndNeverReloadsTopWindow() {
        val source = GameFrameReloadBridgeScript.source

        assertTrue(source.contains("getElementById('htmlWrap')"))
        assertTrue(source.contains("game.contentWindow.location.reload()"))
        assertTrue(source.contains("game.setAttribute('src', source)"))
        assertFalse(source.contains("window.location.reload()"))
    }

    @Test
    fun scriptReportsTargetAfterDomIsAvailable() {
        val source = GameFrameReloadBridgeScript.source

        assertTrue(source.contains("kind: 'target'"))
        assertTrue(source.contains("DOMContentLoaded"))
        assertTrue(source.contains("available:"))
    }

    @Test
    fun scriptObservesHtmlWrapInsertedAfterDomContentLoaded() {
        val source = GameFrameReloadBridgeScript.source

        assertTrue(source.contains("MutationObserver"))
        assertTrue(source.contains("observer.observe"))
    }

    @Test
    fun scriptDoesNotInstallRightClickOrContextMenuHandlers() {
        val source = GameFrameReloadBridgeScript.source

        assertFalse(source.contains("contextmenu"))
        assertFalse(source.contains("rightClickEnabled"))
        assertFalse(source.contains("secondary_click"))
    }

    @Test
    fun coordinatorCompletesMatchingRequestOnlyOnce() {
        val coordinator = GameFrameReloadRequestCoordinator(
            requestIdFactory = { "request-1" },
        )
        val results = mutableListOf<String>()
        val request = coordinator.start(results::add)

        assertEquals("request-1", request)
        assertFalse(coordinator.complete("wrong", "reloaded"))
        assertTrue(coordinator.complete(request, "reloaded"))
        assertFalse(coordinator.complete(request, "reloaded"))
        assertEquals(listOf("reloaded"), results)
    }

    @Test
    fun coordinatorCancelsPendingRequestOnlyOnce() {
        val coordinator = GameFrameReloadRequestCoordinator(
            requestIdFactory = { "request-1" },
        )
        val results = mutableListOf<String>()
        coordinator.start(results::add)

        assertTrue(coordinator.cancel("blocked"))
        assertFalse(coordinator.cancel("blocked"))
        assertEquals(listOf("blocked"), results)
    }

    @Test
    fun canceledDocumentCannotCompleteTheNextRequest() {
        var nextId = 0
        val coordinator = GameFrameReloadRequestCoordinator(
            requestIdFactory = { "request-${++nextId}" },
        )
        val results = mutableListOf<String>()
        val oldRequest = coordinator.start(results::add)
        coordinator.cancel("blocked")
        val currentRequest = coordinator.start(results::add)

        assertFalse(coordinator.complete(oldRequest, "reloaded"))
        assertTrue(coordinator.hasPending)
        assertTrue(coordinator.complete(currentRequest, "html_wrap_not_found"))
        assertEquals(listOf("blocked", "html_wrap_not_found"), results)
    }
}
