package app.yahagi.kancollebrowser.subtitles

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ShipSubtitlePolicyTest {
    private fun position(id: String = "current", x: Any = 0.25, y: Any = 0.75) =
        JSONObject().put("documentId", id).put("x", x).put("y", y)

    @Test fun subtitlesStartDisabledAndLocked() {
        assertFalse(ShipSubtitleConfig().enabled)
        assertTrue(ShipSubtitleConfig().locked)
        assertEquals("medium", ShipSubtitleConfig().fontSize)
        assertEquals(0.5, ShipSubtitleConfig().x, 0.0)
        assertEquals(0.9, ShipSubtitleConfig().y, 0.0)
    }

    @Test fun androidPageScaleConvertsPhysicalPixelsToDensityIndependentPixels() {
        assertEquals(.3, ShipSubtitlePolicy.displayScale(.9, 3.0)!!, .00001)
        assertEquals(1.0, ShipSubtitlePolicy.displayScale(3.0, 3.0)!!, .00001)
        assertNull(ShipSubtitlePolicy.displayScale(Double.NaN, 3.0))
        assertNull(ShipSubtitlePolicy.displayScale(.9, 0.0))
    }

    @Test fun dragRequiresEnabledUnlockedCurrentDocumentAndValidCoordinates() {
        val unlocked = ShipSubtitleConfig(enabled = true, locked = false)
        assertNotNull(ShipSubtitlePolicy.position(position(), unlocked, "current"))
        assertNull(ShipSubtitlePolicy.position(position(), unlocked.copy(enabled = false), "current"))
        assertNull(ShipSubtitlePolicy.position(position(), unlocked.copy(locked = true), "current"))
        assertNull(ShipSubtitlePolicy.position(position("previous"), unlocked, "current"))
        assertNull(ShipSubtitlePolicy.position(position(x = 1.1), unlocked, "current"))
        assertNull(ShipSubtitlePolicy.position(position(y = -0.1), unlocked, "current"))
        assertNull(ShipSubtitlePolicy.position(position(x = "0.5"), unlocked, "current"))
    }

    @Test fun onlyGameDocumentsAtTheSourceOriginCanHandshake() {
        val origin = "https://w01.kancolle-server.com"
        assertTrue(ShipSubtitlePolicy.isGameDocument("$origin/kcs2/index.php?version=1", origin))
        assertFalse(ShipSubtitlePolicy.isGameDocument("$origin/account", origin))
        assertFalse(ShipSubtitlePolicy.isGameDocument("$origin/kcs2-other/", origin))
        assertFalse(ShipSubtitlePolicy.isGameDocument("https://foreign.dmm.com/kcs2/index.php", origin))
        assertFalse(ShipSubtitlePolicy.isGameDocument("http://w01.kancolle-server.com/kcs2/", origin))
        assertFalse(ShipSubtitlePolicy.isGameDocument("${origin}:444/kcs2/", origin))
    }

    @Test fun configRejectsInvalidFontAndCoordinatesWithoutLosingPreviousValues() {
        val config = ShipSubtitleConfig(x = .2, y = .8).merge(mapOf("enabled" to true, "fontSize" to "huge", "x" to Double.NaN, "y" to 2.0))
        assertTrue(config.enabled)
        assertEquals("medium", config.fontSize)
        assertEquals(.2, config.x, 0.0)
        assertEquals(.8, config.y, 0.0)
    }

    @Test fun anOldDocumentCannotRejoinOrSendPositionsAfterARefresh() {
        val epochs = ShipSubtitleDocumentEpochs()
        val origin = "https://w01.kancolle-server.com"
        assertTrue(epochs.accept(origin, "old-document", 100.0))
        assertTrue(epochs.accept(origin, "new-document", 200.0))
        assertFalse(epochs.isCurrent(origin, "old-document"))
        assertFalse(epochs.accept(origin, "old-document", 100.0))
        assertFalse(epochs.accept(origin, "different-document-at-old-epoch", 200.0))
        assertTrue(epochs.isCurrent(origin, "new-document"))
        assertTrue(epochs.accept(origin, "new-document", 200.0))
        assertFalse(epochs.accept(origin, "invalid-document", Double.NaN))
        val nextServer = "https://w02.kancolle-server.com"
        assertTrue(epochs.accept(nextServer, "new-server-document", 300.0))
        assertFalse(epochs.isCurrent(origin, "new-document"))
        assertTrue(epochs.isCurrent(nextServer, "new-server-document"))
        assertFalse(epochs.accept(origin, "new-document", 200.0))
    }
}
