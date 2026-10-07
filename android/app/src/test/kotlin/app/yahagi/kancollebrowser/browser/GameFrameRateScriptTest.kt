package app.yahagi.kancollebrowser.browser

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GameFrameRateScriptTest {
    @Test
    fun mapsWireModesAndFallsBackToAuto() {
        assertEquals(GameFrameRateMode.AUTO, GameFrameRateMode.fromWireName("auto"))
        assertEquals(GameFrameRateMode.STABLE_60, GameFrameRateMode.fromWireName("stable60"))
        assertEquals(GameFrameRateMode.STABLE_30, GameFrameRateMode.fromWireName("stable30"))
        assertEquals(GameFrameRateMode.HIGH_REFRESH, GameFrameRateMode.fromWireName("highRefresh"))
        assertEquals(GameFrameRateMode.AUTO, GameFrameRateMode.fromWireName("prefer60"))
        assertEquals(GameFrameRateMode.AUTO, GameFrameRateMode.fromWireName("future-mode"))
    }

    @Test
    fun runtimeBridgeScriptControlsTheTickerInsideEachDocument() {
        val script = GameFrameRateBridgeScript.source

        assertTrue(script.contains("window.YahagiFrameRate"))
        assertTrue(script.contains("bridge.postMessage"))
        assertTrue(script.contains("bridge.onmessage"))
        assertTrue(script.contains("window.createjs.Ticker"))
        assertTrue(script.contains("getMeasuredFPS"))
        assertTrue(script.contains("current.RAF_SYNCHED"))
        assertTrue(script.contains("current.TIMEOUT"))
        assertTrue(script.contains("highRefresh"))
        assertTrue(script.contains("current.timingMode = current.RAF"))
        assertTrue(script.contains("current._handleSynch = state.wrapper"))
        assertTrue(script.contains("renderTexture != null"))
        assertTrue(script.contains("this.view !== mainCanvas"))
        assertTrue(script.contains("renderCpuP95Ms"))
        assertTrue(script.contains("configuredFps"))
        assertTrue(script.contains("getSnapshot"))
        assertTrue(script.contains("__yahagiFrameRateRuntime"))
        assertTrue(script.contains("window.clearInterval(intervalId)"))
        assertFalse(script.contains("window.requestAnimationFrame ="))
        assertFalse(script.contains("fetch("))
        assertFalse(script.contains("XMLHttpRequest"))
        assertFalse(script.contains("dispatchEvent"))
    }
}
