package app.yahagi.kancollebrowser.browser

import android.app.Activity
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.ScriptHandler
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import app.yahagi.kancollebrowser.capture.CaptureOriginPolicy
import org.json.JSONObject

enum class GameFrameRateTarget(val wireName: String) {
    FPS_30("fps30"),
    FPS_60("fps60"),
    HIGH_REFRESH("highRefresh");

    companion object {
        fun fromWireName(value: String?): GameFrameRateTarget? =
            entries.firstOrNull { it.wireName == value }
    }
}

class GameFrameRateBridge(
    private val activity: Activity,
    private val originPolicy: CaptureOriginPolicy = CaptureOriginPolicy(),
) {
    private companion object {
        const val SAMPLE_MAX_AGE_MILLIS = 3_000L
    }

    private var attachedWebView: WebView? = null
    private var scriptHandler: ScriptHandler? = null
    private var listenerInstalled = false
    private var target = GameFrameRateTarget.FPS_60
    private var foreground = false
    private val replyProxies = GameFrameRateReplyRegistry<JavaScriptReplyProxy>()
    private var latestFps: Double? = null
    private var latestFpsAtMillis = 0L
    private var latestPerformanceSample: GameFramePerformanceSample? = null
    private var originalLayerType: Int? = null

    fun isSupported(): Boolean =
        WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT) &&
            WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)

    @Throws(GameFrameRateBridgeException::class)
    fun configure(target: GameFrameRateTarget) {
        if (this.target != target) clearSample()
        this.target = target
        if (!isSupported()) {
            throw GameFrameRateBridgeException(
                "frame_rate_unsupported",
                "This Android WebView does not support frame-level messaging.",
            )
        }

        val webViews = mutableListOf<WebView>()
        collectWebViews(activity.window.decorView, webViews)
        if (webViews.size != 1) {
            throw GameFrameRateBridgeException(
                if (webViews.isEmpty()) "webview_not_found" else "multiple_webviews",
                "Expected one game WebView but found ${webViews.size}.",
            )
        }

        val webView = webViews.single()
        if (attachedWebView === webView && listenerInstalled && scriptHandler != null) {
            postTargetToAllFrames()
            return
        }

        disable()
        try {
            WebViewCompat.addWebMessageListener(
                webView,
                GameFrameRateBridgeScript.objectName,
                originPolicy.allowedOriginRules,
                ::onPostMessage,
            )
            listenerInstalled = true
            scriptHandler = WebViewCompat.addDocumentStartJavaScript(
                webView,
                GameFrameRateBridgeScript.source,
                originPolicy.allowedOriginRules,
            )
            attachedWebView = webView
        } catch (error: RuntimeException) {
            disableWebView(webView)
            throw GameFrameRateBridgeException(
                "frame_rate_configuration_failed",
                error.message ?: "Unable to configure frame-rate messaging.",
            )
        }
    }

    fun apply(target: GameFrameRateTarget) {
        if (this.target != target) clearSample()
        this.target = target
        postTargetToAllFrames()
    }

    fun setForeground(foreground: Boolean) {
        if (this.foreground == foreground) return
        this.foreground = foreground
        clearSample()
        postTargetToAllFrames()
    }

    fun measuredFps(): Double? {
        if (!foreground) return null
        val fps = latestFps ?: return null
        if (SystemClock.elapsedRealtime() - latestFpsAtMillis > SAMPLE_MAX_AGE_MILLIS) {
            return null
        }
        return fps
    }

    /** A cached one-second game sample. Reading it does not schedule more drawing. */
    fun performanceSnapshot(): Map<String, Any?> {
        val age = if (latestFpsAtMillis == 0L) null else
            SystemClock.elapsedRealtime() - latestFpsAtMillis
        val fresh = foreground && age != null && age <= SAMPLE_MAX_AGE_MILLIS
        return mapOf(
            "target" to target.wireName,
            "sampleAgeMs" to age,
            "fresh" to fresh,
            "sample" to if (fresh) latestPerformanceSample?.toMap() else null,
            "layerMode" to when (attachedWebView?.layerType) {
                View.LAYER_TYPE_HARDWARE -> "hardware"
                View.LAYER_TYPE_NONE -> "platformDefault"
                else -> "unknown"
            },
            "hardwareAccelerated" to attachedWebView?.isHardwareAccelerated,
            "displayRefreshRate" to attachedWebView?.display?.refreshRate,
        )
    }

    /** Transient A/B override; restore on dispose and never select software rendering. */
    fun setLayerMode(mode: String): Boolean {
        val webView = attachedWebView ?: return false
        val layer = when (mode) {
            "hardware" -> View.LAYER_TYPE_HARDWARE
            "platformDefault" -> View.LAYER_TYPE_NONE
            "restore" -> originalLayerType ?: webView.layerType
            else -> return false
        }
        if (originalLayerType == null && mode != "restore") {
            originalLayerType = webView.layerType
        }
        webView.setLayerType(layer, null)
        if (mode == "restore") originalLayerType = null
        return true
    }

    private fun clearSample() {
        latestFps = null
        latestFpsAtMillis = 0L
        latestPerformanceSample = null
    }

    fun dispose() = disable()

    @Suppress("UNUSED_PARAMETER")
    private fun onPostMessage(
        webView: WebView,
        message: WebMessageCompat,
        sourceOrigin: android.net.Uri,
        isMainFrame: Boolean,
        replyProxy: JavaScriptReplyProxy,
    ) {
        if (webView !== attachedWebView) return
        val origin = sourceOrigin.toString()
        if (origin.length > 2_048 || !originPolicy.isAllowed(origin)) return
        val payload = try {
            val data = message.data ?: return
            if (data.length > 8_192) return
            JSONObject(data)
        } catch (_: Exception) {
            return
        }

        when (payload.opt("kind")) {
            "ready" -> {
                if (!replyProxies.registerReady(origin, replyProxy)) return
                try {
                    postTarget(replyProxy)
                } catch (_: RuntimeException) {
                    replyProxies.remove(origin, replyProxy)
                }
            }
            "sample" -> {
                if (!replyProxies.contains(origin, replyProxy)) return
                val sample = GameFramePerformanceSample.fromJson(payload) ?: return
                if (sample.target != target.wireName) return
                replyProxies.recordSample(origin, replyProxy)
                if (!foreground) return
                latestPerformanceSample = sample
                latestFps = if (sample.isUsableForAuto(target.wireName)) sample.fps else null
                latestFpsAtMillis = SystemClock.elapsedRealtime()
            }
        }
    }

    private fun postTargetToAllFrames() {
        replyProxies.broadcast(::postTarget)
    }

    private fun postTarget(replyProxy: JavaScriptReplyProxy) {
        replyProxy.postMessage(
            JSONObject()
                .put("target", target.wireName)
                .put("foreground", foreground)
                .toString(),
        )
    }

    private fun disable() {
        val webView = attachedWebView
        if (webView != null) originalLayerType?.let { webView.setLayerType(it, null) }
        originalLayerType = null
        scriptHandler?.remove()
        scriptHandler = null
        if (webView != null) disableWebView(webView)
        attachedWebView = null
        replyProxies.clear()
        clearSample()
    }

    private fun disableWebView(webView: WebView) {
        if (listenerInstalled) {
            try {
                WebViewCompat.removeWebMessageListener(
                    webView,
                    GameFrameRateBridgeScript.objectName,
                )
            } catch (_: RuntimeException) {
                // Navigation already destroyed the previous JavaScript contexts.
            }
        }
        listenerInstalled = false
    }

    private fun collectWebViews(view: View, results: MutableList<WebView>) {
        if (view is WebView) results.add(view)
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                collectWebViews(view.getChildAt(index), results)
            }
        }
    }
}

class GameFrameRateBridgeException(
    val code: String,
    override val message: String,
) : RuntimeException(message)
