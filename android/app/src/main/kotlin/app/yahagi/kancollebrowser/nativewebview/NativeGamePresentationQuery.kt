package app.yahagi.kancollebrowser.nativewebview

/** Pure policy for async current-document presentation queries. */
internal class NativeGamePresentationQuery {
    data class Token(val documentEpoch: Long, val queryVersion: Long)
    private var queryVersion = 0L

    fun begin(documentEpoch: Long): Token = Token(documentEpoch, ++queryVersion)

    fun resolve(token: Token, currentDocumentEpoch: Long, result: String?): String? {
        if (token.documentEpoch != currentDocumentEpoch || token.queryVersion != queryVersion) return null
        return when (result) {
            "\"pending\"" -> "pending"
            "\"web\"" -> "web"
            "\"game\"" -> "game"
            else -> null
        }
    }

    companion object {
        // Reads the current DOM without reentering the JavaScript bridge.
        const val SCRIPT = "(function(){return typeof window.__yahagiMobileReadPresentation === 'function' ? window.__yahagiMobileReadPresentation() : null;})()"
    }
}
