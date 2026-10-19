package app.yahagi.kancollebrowser.subtitles

import java.net.URI
import org.json.JSONObject

data class ShipSubtitleConfig(
    val enabled: Boolean = false,
    val fontSize: String = "medium",
    val locked: Boolean = true,
    val x: Double = 0.5,
    val y: Double = 0.9,
) {
    fun merge(arguments: Map<*, *>): ShipSubtitleConfig {
        fun coordinate(key: String, previous: Double): Double =
            (arguments[key] as? Number)?.toDouble()?.takeIf { it.isFinite() && it in 0.0..1.0 } ?: previous
        return copy(
            enabled = arguments["enabled"] as? Boolean ?: enabled,
            fontSize = (arguments["fontSize"] as? String)?.takeIf { it in setOf("small", "medium", "large") } ?: fontSize,
            locked = arguments["locked"] as? Boolean ?: locked,
            x = coordinate("x", x),
            y = coordinate("y", y),
        )
    }

    fun toJson(): JSONObject = JSONObject().put("kind", "config")
        .put("enabled", enabled).put("fontSize", fontSize).put("locked", locked).put("x", x).put("y", y)
}

object ShipSubtitlePolicy {
    fun displayScale(pageScale: Double, density: Double): Double? =
        if (pageScale.isFinite() && pageScale > 0 && density.isFinite() && density > 0) pageScale / density else null

    fun position(message: JSONObject, config: ShipSubtitleConfig, activeDocumentId: String): Pair<Double, Double>? {
        if (!config.enabled || config.locked || message.optString("documentId") != activeDocumentId) return null
        val x = (message.opt("x") as? Number)?.toDouble() ?: return null
        val y = (message.opt("y") as? Number)?.toDouble() ?: return null
        if (!x.isFinite() || !y.isFinite() || x !in 0.0..1.0 || y !in 0.0..1.0) return null
        return x to y
    }

    fun isGameDocument(url: String, sourceOrigin: String): Boolean = try {
        val document = URI(url)
        val origin = URI(sourceOrigin)
        document.scheme == "https" && document.scheme == origin.scheme &&
            document.host.equals(origin.host, ignoreCase = true) &&
            (document.port == -1 || document.port == 443) &&
            (origin.port == -1 || origin.port == 443) && document.rawUserInfo == null &&
            (document.path == "/kcs2" || document.path.startsWith("/kcs2/"))
    } catch (_: Exception) { false }
}

/** One active game frame per WebView; refresh and server switches replace its previous JS world. */
class ShipSubtitleDocumentEpochs {
    private data class Epoch(val origin: String, val id: String, val startedAt: Double)
    private var latest: Epoch? = null

    fun accept(origin: String, documentId: String, startedAt: Double): Boolean {
        if (!startedAt.isFinite() || startedAt <= 0) return false
        val previous = latest
        if (previous != null) {
            if (startedAt < previous.startedAt) return false
            if (startedAt == previous.startedAt && (documentId != previous.id || origin != previous.origin)) return false
        }
        latest = Epoch(origin, documentId, startedAt)
        return true
    }

    fun isCurrent(origin: String, documentId: String): Boolean = latest?.let { it.origin == origin && it.id == documentId } == true
    fun clear() { latest = null }
}
