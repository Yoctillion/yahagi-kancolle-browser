package app.yahagi.kancollebrowser.browser

/** Only a confirmed absence may skip the frame verification used when applying mods. */
internal enum class GameModPagePresence { ABSENT, PRESENT, UNKNOWN }

internal object GameModPagePresencePolicy {
    fun classify(webViewCount: Int, address: String?, knownTarget: Boolean): GameModPagePresence {
        if (knownTarget) return GameModPagePresence.PRESENT
        if (webViewCount == 0) return GameModPagePresence.ABSENT
        if (webViewCount != 1) return GameModPagePresence.UNKNOWN
        if (address == "about:blank") return GameModPagePresence.ABSENT
        // A loading or unbound page, including OOI, must still pass the frame probe.
        return GameModPagePresence.UNKNOWN
    }
}
