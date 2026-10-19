package app.yahagi.kancollebrowser.subtitles

import android.content.Context
import android.view.View
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import app.yahagi.kancollebrowser.capture.CaptureOriginPolicy
import java.io.ByteArrayInputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Uses an actual cross-origin game iframe and Chromium message transport; no game account or network. */
@RunWith(AndroidJUnit4::class)
class ShipSubtitleWebViewTest {
    @Test fun crossOriginDocumentStartReceivesFullCatalogAndKeepsProxyIdentity() {
        assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT))
        assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER))
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = ApplicationProvider.getApplicationContext<Context>()
        val script = context.assets.open(ShipSubtitleBridge.SCRIPT_ASSET).bufferedReader().use { it.readText() }
        val rawQuotes = context.assets.open("flutter_assets/assets/data/subtitles/zh-cn.json").bufferedReader().use { it.readText() }
        assertTrue("Exercise the entire bundled catalog", rawQuotes.length > 5_000_000)
        val parsedQuotes = JSONObject(rawQuotes)
        val expected = "睦月：" + parsedQuotes.getJSONObject("1").getString("1")
        // Keep the actual 5.55 MB ASCII escaped payload rather than reparsing to a shorter string.
        val catalog = "{\"kind\":\"catalog\",\"version\":\"test\",\"quotes\":$rawQuotes}"
        val done = CountDownLatch(1)
        val readyCount = AtomicInteger()
        val proxyAtReady = AtomicReference<JavaScriptReplyProxy>()
        val configuredScale = AtomicReference<Double>()
        val configSent = AtomicBoolean()
        val result = AtomicReference<JSONObject>()
        val error = AtomicReference<String>()
        var webView: WebView? = null
        fun configureAtRequestedScale(pageScale: Double) {
            // Document-start runs before WebView necessarily applies initialScale.
            if (kotlin.math.abs(pageScale - .9) > .02) return
            val proxy = proxyAtReady.get() ?: return
            if (!configSent.compareAndSet(false, true)) return
            configuredScale.set(pageScale)
            proxy.postMessage(ShipSubtitleConfig(enabled = true, locked = true).toJson()
                .put("displayScale", ShipSubtitlePolicy.displayScale(pageScale, context.resources.displayMetrics.density.toDouble())).toString())
        }
        try {
            instrumentation.runOnMainSync {
                webView = WebView(context).apply {
                    settings.javaScriptEnabled = true
                    settings.useWideViewPort = true
                    settings.loadWithOverviewMode = false
                    setInitialScale(90)
                    measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(648, View.MeasureSpec.EXACTLY))
                    layout(0, 0, 1080, 648)
                    webViewClient = object : WebViewClient() {
                        override fun onScaleChanged(view: WebView?, oldScale: Float, newScale: Float) {
                            configureAtRequestedScale(newScale.toDouble())
                        }
                        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse {
                            val html = if (request.url.host == "www.dmm.com") {
                                "<html><meta name='viewport' content='width=1200'><body style='margin:0'><iframe style='border:0' src='https://w01.kancolle-server.com/kcs2/index.php' width='1200' height='720'></iframe></body></html>"
                            } else gameHtml()
                            return WebResourceResponse("text/html", "UTF-8", ByteArrayInputStream(html.toByteArray()))
                        }
                    }
                    WebViewCompat.addWebMessageListener(this, ShipSubtitleBridge.OBJECT_NAME, CaptureOriginPolicy().allowedOriginRules) { sender, message, origin, mainFrame, proxy ->
                        try {
                            val payload = JSONObject(message.data!!)
                            when (payload.optString("kind")) {
                                "ready" -> {
                                    assertFalse("Only the game iframe handshakes", mainFrame)
                                    assertEquals("https://w01.kancolle-server.com", origin.toString())
                                    assertTrue(ShipSubtitlePolicy.isGameDocument(payload.getString("url"), origin.toString()))
                                    assertTrue(payload.getDouble("documentStartedAt") > 0)
                                    readyCount.incrementAndGet()
                                    proxyAtReady.set(proxy)
                                    proxy.postMessage(catalog)
                                    proxy.postMessage(JSONObject().put("kind", "ships").put("ships", JSONArray().put(JSONObject().put("id", 1).put("fileName", "testship").put("name", "睦月"))).toString())
                                    @Suppress("DEPRECATION")
                                    val pageScale = sender.scale.toDouble()
                                    configureAtRequestedScale(pageScale)
                                }
                                "probe" -> {
                                    assertSame("Reply proxy is stable for later messages from this frame", proxyAtReady.get(), proxy)
                                    @Suppress("DEPRECATION")
                                    val nativeScale = sender.scale.toDouble()
                                    result.set(payload.put("nativePageScale", nativeScale).put("density", context.resources.displayMetrics.density.toDouble()))
                                    done.countDown()
                                }
                            }
                        } catch (failure: Throwable) {
                            error.set(failure.toString())
                            done.countDown()
                        }
                    }
                    WebViewCompat.addDocumentStartJavaScript(this, script, CaptureOriginPolicy().allowedOriginRules)
                    loadUrl("https://www.dmm.com/subtitle-fixture")
                }
            }
            assertTrue("Game frame did not return a subtitle: ${error.get()}", done.await(30, TimeUnit.SECONDS))
            assertNull(error.get())
            println("ShipSubtitleWebView metrics=${result.get()}")
            assertEquals(1, readyCount.get())
            assertEquals(expected, result.get().getString("text").replace("\n", ""))
            assertEquals("none", result.get().getString("pointerEvents"))
            assertEquals(0, result.get().getInt("handles"))
            assertEquals(1.0, result.get().getDouble("childScale"), .001)
            // Match the production bridge after its requested scale is applied.
            assertEquals(configuredScale.get(), result.get().getDouble("nativePageScale"), .02)
            val displayedFont = result.get().getDouble("cssFontSize") * result.get().getDouble("nativePageScale") / result.get().getDouble("density")
            assertTrue("Font should remain at least 15dp: $displayedFont; metrics=${result.get()}", displayedFont >= 14.9)
        } finally {
            instrumentation.runOnMainSync { webView?.destroy() }
        }
    }

    private fun gameHtml(): String = """
        <!doctype html><html><body style="margin:0"><canvas width="1200" height="720"></canvas><script>
        window.Howler = {_howls: []};
        window.Howl = function(src) { this._src = src; this.events = {}; Howler._howls.push(this); };
        Howl.prototype.on = function(event, cb) { (this.events[event] || (this.events[event] = [])).push(cb); return this; };
        Howl.prototype.off = function(event, cb) { this.events[event] = (this.events[event] || []).filter(function(x) {return x !== cb;}); return this; };
        Howl.prototype.play = function() { return 7; };
        Howl.prototype.duration = function() { return 3; };
        var timer = setInterval(function() {
          if (!document.querySelector('[data-yahagi-ship-subtitle="root"]')) return;
          clearInterval(timer);
          var audio = new Howl('/kcs/sound/kctestship/139081.mp3');
          audio.play();
          (audio.events.play || []).forEach(function(cb) {cb(7);});
          var text = document.querySelector('[data-yahagi-ship-subtitle="text"]');
          YahagiShipSubtitles.postMessage(JSON.stringify({kind:'probe', text:text.textContent,
            pointerEvents:getComputedStyle(text).pointerEvents,
            childScale:visualViewport.scale, innerWidth:innerWidth,
            cssFontSize:parseFloat(getComputedStyle(text).fontSize),
            handles:document.querySelectorAll('[data-yahagi-ship-subtitle="handle"]').length}));
        }, 30);
        </script></body></html>
    """.trimIndent()
}
