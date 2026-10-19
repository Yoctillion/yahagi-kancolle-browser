package app.yahagi.kancollebrowser.browser

import org.junit.Assert.assertEquals
import org.junit.Test

class GameModPagePresenceTest {
    @Test fun onlyConfirmedAbsenceMaySkipVerification() {
        assertEquals(GameModPagePresence.ABSENT, GameModPagePresencePolicy.classify(0, null, false))
        assertEquals(GameModPagePresence.ABSENT, GameModPagePresencePolicy.classify(1, "about:blank", false))
    }

    @Test fun unboundOrLoadingGameRemainsUnknown() {
        listOf(null, "https://ooi.moe/", "https://www.dmm.com/netgame/social/-/gadgets/=/app_id=854854/",
            "https://w15p.kancolle-server.com/kcs2/index.php", "https://example.com/").forEach {
            assertEquals(GameModPagePresence.UNKNOWN, GameModPagePresencePolicy.classify(1, it, false))
        }
        assertEquals(GameModPagePresence.UNKNOWN, GameModPagePresencePolicy.classify(2, "about:blank", false))
    }

    @Test fun verifiedTargetRequiresReload() {
        assertEquals(GameModPagePresence.PRESENT, GameModPagePresencePolicy.classify(1, null, true))
    }
}
