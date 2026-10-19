package app.yahagi.kancollebrowser.subtitles

import android.app.Activity
import android.net.Uri
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.ScriptHandler
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import app.yahagi.kancollebrowser.capture.CaptureOriginPolicy
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/** Installed before the first navigation, even when disabled, so enabling needs no refresh. */
class ShipSubtitleBridge(
    private val activity: Activity,
    private val channel: MethodChannel,
    private val originPolicy: CaptureOriginPolicy = CaptureOriginPolicy(),
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "app.yahagi.kancollebrowser/ship_subtitles"
        const val OBJECT_NAME = "YahagiShipSubtitles"
        const val SCRIPT_ASSET = "flutter_assets/assets/scripts/ship_subtitles.js"
    }

    private data class Document(
        val id: String,
        val origin: String,
        val proxy: JavaScriptReplyProxy,
        var catalogRevision: Long = -1,
        var shipsRevision: Long = -1,
    )

    private var config = ShipSubtitleConfig()
    private var webView: WebView? = null
    private var scriptHandler: ScriptHandler? = null
    private var listenerInstalled = false
    private var scriptSource: String? = null
    private var disposed = false
    private var catalog = JSONObject().put("kind", "catalog").put("version", "").put("quotes", JSONObject()).toString()
    private var ships = JSONObject().put("kind", "ships").put("ships", JSONArray()).toString()
    private var catalogRevision = 0L
    private var shipsRevision = 0L
    private val documents = linkedMapOf<String, Document>()
    private val documentEpochs = ShipSubtitleDocumentEpochs()
    private var requestedPageScale: Double? = null
    private var displayScale = 1.0
    private val layoutListener = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> refreshDisplayScale() }

    init { channel.setMethodCallHandler(this) }

    fun isSupported(): Boolean =
        WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT) &&
            WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isSupported" -> result.success(isSupported())
                "ensureInstalled" -> { ensureInstalled(); result.success(null) }
                "configure" -> {
                    config = config.merge(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                    ensureInstalled()
                    broadcast { postConfig(it) }
                    result.success(null)
                }
                "setCatalog" -> {
                    val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    val quotes = arguments["quotes"] as? Map<*, *> ?: emptyMap<Any, Any>()
                    val next = JSONObject().put("kind", "catalog")
                        .put("version", arguments["version"] as? String ?: "")
                        .put("quotes", JSONObject(quotes)).toString()
                    if (catalog != next) { catalog = next; catalogRevision++; broadcast { postCatalog(it) } }
                    result.success(null)
                }
                "setShips" -> {
                    val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    val entries = arguments["ships"] as? List<*> ?: emptyList<Any>()
                    val next = JSONObject().put("kind", "ships").put("ships", JSONArray(entries)).toString()
                    if (ships != next) { ships = next; shipsRevision++; broadcast { postShips(it) } }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("ship_subtitle_configuration_failed", error.message, null)
        }
    }

    /** No WebView yet is normal during app startup; keep config and retry from onCreated. */
    fun ensureInstalled() {
        if (disposed) return
        // The same attached WebView survives ordinary Flutter layout changes.
        // Only search the view tree again after it detaches or is replaced.
        if (webView?.isAttachedToWindow == true && listenerInstalled && scriptHandler != null) return
        if (!isSupported()) return
        val views = mutableListOf<WebView>()
        collect(activity.window.decorView, views)
        if (views.size != 1) return
        val target = views.single()
        if (webView === target && listenerInstalled && scriptHandler != null) return
        detach()
        val source = scriptSource ?: activity.assets.open(SCRIPT_ASSET).bufferedReader().use { it.readText() }.also { scriptSource = it }
        webView = target
        try {
            WebViewCompat.addWebMessageListener(target, OBJECT_NAME, originPolicy.allowedOriginRules, ::onMessage)
            listenerInstalled = true
            scriptHandler = WebViewCompat.addDocumentStartJavaScript(target, source, originPolicy.allowedOriginRules)
            target.addOnLayoutChangeListener(layoutListener)
            refreshDisplayScale()
        } catch (error: RuntimeException) {
            detach()
            throw error
        }
    }

    /** pageScale is Android's physical pixels per CSS pixel, e.g. setInitialScale(90) -> 0.9. */
    @Suppress("DEPRECATION")
    fun refreshDisplayScale(pageScale: Double? = null) {
        if (pageScale != null && pageScale.isFinite() && pageScale > 0) requestedPageScale = pageScale
        val rawScale = requestedPageScale ?: webView?.scale?.toDouble() ?: return
        val density = activity.resources.displayMetrics.density.toDouble()
        val next = ShipSubtitlePolicy.displayScale(rawScale, density) ?: return
        if (kotlin.math.abs(next - displayScale) < 0.0001) return
        displayScale = next
        broadcast { postConfig(it) }
    }

    @Suppress("UNUSED_PARAMETER")
    private fun onMessage(
        sender: WebView,
        message: WebMessageCompat,
        sourceOrigin: Uri,
        isMainFrame: Boolean,
        proxy: JavaScriptReplyProxy,
    ) {
        if (disposed || sender !== webView) return
        val origin = sourceOrigin.toString()
        if (!originPolicy.isAllowed(origin)) return
        val raw = message.data ?: return
        if (raw.length > 4096) return
        val payload = try { JSONObject(raw) } catch (_: Exception) { return }
        val id = payload.optString("documentId")
        if (id.length !in 8..128 || !id.matches(Regex("[a-zA-Z0-9-]+"))) return
        if (payload.optString("kind") == "ready") {
            if (!ShipSubtitlePolicy.isGameDocument(payload.optString("url"), origin)) return
            val startedAt = (payload.opt("documentStartedAt") as? Number)?.toDouble() ?: return
            if (!documentEpochs.accept(origin, id, startedAt)) return
            // Reject queued messages from the previous game document even if pagehide never ran.
            documents.values.toList().filter { it.id != id }.forEach {
                safely(it) { previous -> previous.proxy.postMessage(JSONObject().put("kind", "dispose").toString()) }
                documents.remove(it.id)
            }
            // A reply proxy belongs to one frame's JS object; replace only that frame's old document.
            documents.entries.removeAll { it.value.proxy === proxy && it.key != id }
            if (documents.size >= 8 && id !in documents) documents.remove(documents.keys.first())
            val document = documents[id]?.takeIf { it.proxy === proxy && it.origin == origin }
                ?: Document(id, origin, proxy).also { documents[id] = it }
            safely(document) { postCatalog(it); postShips(it); postConfig(it) }
            return
        }
        val document = documents[id] ?: return
        if (document.proxy !== proxy || document.origin != origin || !documentEpochs.isCurrent(origin, id)) return
        when (payload.optString("kind")) {
            "gone" -> documents.remove(id)
            "position" -> {
                val position = ShipSubtitlePolicy.position(payload, config, document.id) ?: return
                config = config.copy(x = position.first, y = position.second)
                channel.invokeMethod("positionChanged", mapOf("x" to config.x, "y" to config.y))
            }
        }
    }

    private fun postConfig(document: Document) { document.proxy.postMessage(config.toJson().put("displayScale", displayScale).toString()) }
    private fun postCatalog(document: Document) {
        if (document.catalogRevision == catalogRevision) return
        document.proxy.postMessage(catalog)
        document.catalogRevision = catalogRevision
    }
    private fun postShips(document: Document) {
        if (document.shipsRevision == shipsRevision) return
        document.proxy.postMessage(ships)
        document.shipsRevision = shipsRevision
    }
    private fun safely(document: Document, action: (Document) -> Unit) {
        try { action(document) } catch (_: RuntimeException) { documents.remove(document.id) }
    }
    private fun broadcast(action: (Document) -> Unit) { documents.values.toList().forEach { safely(it, action) } }

    private fun detach() {
        broadcast { it.proxy.postMessage(JSONObject().put("kind", "dispose").toString()) }
        documents.clear()
        documentEpochs.clear()
        scriptHandler?.remove()
        scriptHandler = null
        webView?.removeOnLayoutChangeListener(layoutListener)
        if (listenerInstalled) webView?.let {
            try { WebViewCompat.removeWebMessageListener(it, OBJECT_NAME) } catch (_: RuntimeException) { /* Already destroyed. */ }
        }
        listenerInstalled = false
        webView = null
    }

    fun dispose() {
        if (disposed) return
        detach()
        disposed = true
        channel.setMethodCallHandler(null)
        scriptSource = null
    }

    private fun collect(view: View, results: MutableList<WebView>) {
        if (view is WebView) results.add(view)
        if (view is ViewGroup) for (index in 0 until view.childCount) collect(view.getChildAt(index), results)
    }
}
