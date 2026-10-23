package app.yahagi.kancollebrowser.browser

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.yahagi.kancollebrowser.nativewebview.NativeGamePresentationBridge
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Pass the original Dart runtime as alignmentScriptBase64; no duplicate JS fixture is kept. */
@RunWith(AndroidJUnit4::class)
class OoiViewportSmokeTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val policy = FixedCanvasScalePolicy()
    private val pageFinishes = AtomicInteger()
    private val fits = AtomicInteger()
    private val scaleFailures = AtomicInteger()
    @Volatile private var lastScaleError: String? = null
    private val applier = FixedCanvasScaleApplier()
    private lateinit var view: FailingScaleWebView

    @Test
    fun originalScriptFitsOoiIframeAndEmbedAtRepeatedSizesWithoutReload() = withWebView { script ->
        for (tag in listOf("iframe", "embed")) {
            load(
                "https://ooi.moe/poi",
                "<div id='flashWrap'><$tag id='externalswf' width='1280' height='800'></$tag></div>",
            )
            eval(script)
            val finishes = pageFinishes.get()
            for ((width, height) in listOf(1200 to 720, 700 to 420, 1500 to 900, 900 to 900, 700 to 420)) {
                instrumentation.runOnMainSync { view.layout(0, 0, width, height) }
                eval(script) // Same original-runtime reinjection used by manual fit.
                settle()
                val metrics = JSONObject(eval("""
                    (function(){
                      const frame=document.getElementById('externalswf');
                      const parent=frame.parentElement;
                      const rect=frame.getBoundingClientRect();
                      return {
                        state:window.__yahagiMobileReadPresentation(),
                        viewportWidth:visualViewport.width,viewportHeight:visualViewport.height,
                        scale:Number(parent.style.getPropertyValue('--yahagi-ooi-scale')),
                        width:rect.width,height:rect.height,
                        maxWidth:getComputedStyle(frame).maxWidth,
                        styleCount:document.querySelectorAll('#__yahagi_mobile_ooi_browser__').length
                      };
                    })()
                """.trimIndent()))
                val scale = minOf(metrics.getDouble("viewportWidth") / 1200, metrics.getDouble("viewportHeight") / 720)
                assertEquals("OOI wrapper retains web presentation", "web", metrics.getString("state"))
                assertEquals("$tag fit scale", scale, metrics.getDouble("scale"), 0.00001)
                assertEquals("$tag original CSS width", 1280 * scale, metrics.getDouble("width"), 0.25)
                assertEquals("$tag original CSS height", 800 * scale, metrics.getDouble("height"), 0.25)
                assertEquals("UIkit max-width cannot shrink the frame", "none", metrics.getString("maxWidth"))
                assertEquals("Reinjection keeps one style", 1, metrics.getInt("styleCount"))
            }
            assertEquals("Repeated fitting never reloads the OOI document", finishes, pageFinishes.get())
        }
    }

    @Test
    fun originalScriptManualFitRetriesNativeScaleAfterResetAndException() = withWebView { script ->
        load("https://play.games.dmm.com/game/kancolle/", "<canvas width='1200' height='720'></canvas>")
        fit(script)
        val finishes = pageFinishes.get()
        instrumentation.runOnMainSync {
            view.layout(0, 0, 700, 420)
            view.setInitialScale(100)
        }
        fit(script)
        assertCanvasCorners()
        val beforeFailure = scaleFailures.get()
        instrumentation.runOnMainSync { view.zoomBy(1.25f) }
        settle()
        instrumentation.runOnMainSync { view.failNextScale = true }
        fit(script, allowFailure = true)
        assertEquals("One simulated Android scale error", beforeFailure + 1, scaleFailures.get())
        val beforeRetry = fits.get()
        fit(script)
        assertTrue("Forced game-fit survives native state/scale deduplication", fits.get() > beforeRetry)
        assertCanvasCorners()
        assertEquals("Manual fit does not reload", finishes, pageFinishes.get())
    }

    @Test
    fun productionHelperPreciselyFitsRoundedSlotsAndResetsEffectiveZoomWithoutReload() = withWebView { script ->
        load("https://play.games.dmm.com/game/kancolle/", "<canvas width='1200' height='720'></canvas>")
        fit(script)
        assertCanvasRemainsFitted()
        val finishes = pageFinishes.get()
        // Both 1609x966 and 1614x969 used the same truncated 134% request.
        // The exact ratio must still update when bounds change within that percent.
        for ((width, height) in listOf(1614 to 969, 700 to 420, 1590 to 953, 1609 to 966, 1614 to 969, 900 to 900)) {
            instrumentation.runOnMainSync { view.layout(0, 0, width, height) }
            val beforeFit = fits.get()
            fit(script)
            assertTrue("${width}x$height manual fit applies a native request", fits.get() > beforeFit)
            assertCanvasRemainsFitted()
        }
        instrumentation.runOnMainSync { view.layout(0, 0, 1614, 969) }
        fit(script)
        var baseline = 0f
        instrumentation.runOnMainSync { baseline = view.scale }
        instrumentation.runOnMainSync { view.zoomBy(1.25f) }
        settle()
        var zoomed = 0f
        instrumentation.runOnMainSync { zoomed = view.scale }
        assertTrue("Effective zoom disturbance actually changes scale: $baseline -> $zoomed", zoomed > baseline * 1.05f)
        val beforeRestore = fits.get()
        fit(script)
        assertTrue("Same-percent manual restore applies a new native request", fits.get() > beforeRestore)
        assertCanvasRemainsFitted()
        repeat(3) {
            val beforeRepeat = fits.get()
            fit(script)
            assertTrue("Repeated reinjection applies a native request", fits.get() > beforeRepeat)
            assertCanvasRemainsFitted()
        }
        assertEquals("Repeated native fits preserve the document", finishes, pageFinishes.get())
        assertEquals("CSSOM changes retain the original script text", "true", eval("document.getElementById('__yahagi_mobile_fixed_canvas__').textContent.includes('min-width: 1200px')"))
    }

    @Test
    fun productionHelperCancelStaleAndWebPageCompleteWithoutNativeScaling() = withWebView { script ->
        load("https://play.games.dmm.com/game/kancolle/", "<canvas width='1200' height='720'></canvas>")
        fit(script)
        val completed = CountDownLatch(1)
        val callbacks = AtomicInteger()
        var applied = true
        var nativeBefore = 0
        instrumentation.runOnMainSync {
            nativeBefore = view.nativeScaleCalls
            applier.apply(view, view.width, 100, 1200, 720, { true }) { outcome ->
                applied = outcome.getOrThrow()
                callbacks.incrementAndGet()
                completed.countDown()
            }
            applier.cancel()
        }
        assertTrue("Cancellation completes the pending result", completed.await(5, TimeUnit.SECONDS))
        settle()
        assertEquals("Cancellation completes false", false, applied)
        assertEquals("Late JS callback cannot complete twice", 1, callbacks.get())
        assertEquals("Cancellation never changes native scale", nativeBefore, view.nativeScaleCalls)
        val stale = applyAndWait(current = false)
        assertEquals("A stale view is skipped", false, stale.getOrThrow())
        assertEquals("Stale request never scales", nativeBefore, view.nativeScaleCalls)
        load("https://ooi.moe/login", "<iframe id='externalswf' scrolling='auto'></iframe>")
        eval(script)
        settle()
        nativeBefore = view.nativeScaleCalls
        assertEquals("A web presentation is skipped", false, applyAndWait().getOrThrow())
        assertEquals("Login never receives native scaling", nativeBefore, view.nativeScaleCalls)
        assertEquals("Login frame attribute is retained", "\"auto\"", eval("document.getElementById('externalswf').getAttribute('scrolling')"))
    }

    @Test
    fun originalScriptRestoresViewportMetadataWhenCanvasBecomesOoiWrapper() = withWebView { script ->
        val original = "width=device-width,initial-scale=1,minimum-scale=0.8,maximum-scale=1,user-scalable=no"
        for (originalPresent in listOf(true, false)) {
            instrumentation.runOnMainSync { view.layout(0, 0, 700, 420) }
            load("https://ooi.moe/poi", "<canvas width='1200' height='720'></canvas>")
            if (originalPresent) {
                eval("window.__fixtureViewport=document.querySelector('meta[name=viewport]');window.__fixtureViewport.setAttribute('content',${JSONObject.quote(original)})")
            } else {
                eval("document.querySelectorAll('meta[name=viewport]').forEach(m=>m.remove())")
            }
            fit(script)
            assertCanvasRemainsFitted()
            val nativeBefore = view.nativeScaleCalls
            eval("document.body.innerHTML=\"<div id='flashWrap'><iframe id='externalswf' width='1280' height='800'></iframe></div>\"")
            eval(script)
            settle()
            assertEquals("OOI wrapper releases game presentation", "\"web\"", eval("window.__yahagiMobileReadPresentation()"))
            if (originalPresent) {
                assertEquals("Original viewport node is retained", "true", eval("document.querySelector('meta[name=viewport]')===window.__fixtureViewport"))
                assertEquals("Original viewport content is restored exactly", JSONObject.quote(original), eval("document.querySelector('meta[name=viewport]').getAttribute('content')"))
            } else {
                assertEquals("A game-created viewport is removed on release", "0", eval("document.querySelectorAll('meta[name=viewport]').length"))
            }
            assertEquals("Game clipping is removed with its stylesheet", "\"none\"", eval("getComputedStyle(document.body).clipPath"))
            assertEquals("Web presentation makes no native scale request", nativeBefore, view.nativeScaleCalls)
        }
    }

    @Test
    fun originalScriptManualFitResetsSameOriginOoiChildScroll() = withWebView { script ->
        load(
            "https://ooi.moe/poi",
            """<div id='flashWrap'><iframe id='externalswf' scrolling='auto' srcdoc="&lt;html&gt;&lt;body style='width:2000px;height:1800px'&gt;&lt;/body&gt;&lt;/html&gt;"></iframe></div>""",
        )
        eval("""
            window.__yahagiMobilePresentationRuntimeVersion=3;
            window.__yahagiMobileSyncPresentation=()=> 'web';
            window.__yahagiMobileReadPresentation=()=> 'web';
            window.__staleOoiClosureCalls=0;
            window.__yahagiMobileOoiAlignGame=()=>window.__staleOoiClosureCalls++;
        """.trimIndent())
        eval(script)
        settle()
        assertEquals("Runtime upgrades cached v3 state", "5", eval("window.__yahagiMobilePresentationRuntimeVersion"))
        assertEquals("Upgrade replaces old OOI alignment closure", "0", eval("window.__staleOoiClosureCalls"))
        val finishes = pageFinishes.get()
        eval("document.getElementById('externalswf').contentWindow.scrollTo(113,157)")
        val before = JSONObject(eval("(function(){const w=document.getElementById('externalswf').contentWindow;return {x:w.scrollX,y:w.scrollY};})()"))
        assertTrue("Fixture child actually scrolls", before.getInt("x") > 0 && before.getInt("y") > 0)
        eval(script)
        settle()
        val after = JSONObject(eval("(function(){const w=document.getElementById('externalswf').contentWindow;return {x:w.scrollX,y:w.scrollY};})()"))
        assertEquals("Manual fit resets child horizontal scroll", 0, after.getInt("x"))
        assertEquals("Manual fit resets child vertical scroll", 0, after.getInt("y"))
        assertEquals("Scroll recovery does not reload", finishes, pageFinishes.get())
        eval("window.__removedOoiFrame=document.getElementById('externalswf');document.getElementById('flashWrap').remove();window.__yahagiMobileSyncPresentation()")
        assertEquals("OOI cleanup restores original attribute", "\"auto\"", eval("window.__removedOoiFrame.getAttribute('scrolling')"))
        load("https://ooi.moe/login", "<div id='flashWrap'><iframe id='externalswf' scrolling='no'></iframe></div>")
        eval(script)
        assertEquals("Login keeps its original scrolling attribute", "\"no\"", eval("document.getElementById('externalswf').getAttribute('scrolling')"))
    }

    private fun withWebView(action: (String) -> Unit) {
        val encoded = InstrumentationRegistry.getArguments().getString("alignmentScriptBase64")
        assumeTrue("Pass alignmentScriptBase64 extracted from game_page_alignment_script.dart", !encoded.isNullOrEmpty())
        val script = String(Base64.decode(encoded, Base64.DEFAULT), Charsets.UTF_8)
        try {
            instrumentation.runOnMainSync {
                view = FailingScaleWebView(ApplicationProvider.getApplicationContext<Context>())
                view.settings.javaScriptEnabled = true
                view.settings.useWideViewPort = false
                view.settings.loadWithOverviewMode = false
                view.settings.builtInZoomControls = true
                view.layout(0, 0, 1200, 720)
                view.addJavascriptInterface(
                    NativeGamePresentationBridge(onPresentationStateChanged = { game ->
                        Handler(Looper.getMainLooper()).post {
                            if (game) {
                                view.settings.useWideViewPort = true
                                val scale = policy.nextScalePercent(view.width, view.height, 1200, 720, force = true)
                                if (scale != null) {
                                    val expectedView = view
                                    val expectedWidth = view.width
                                    val expectedHeight = view.height
                                    applier.apply(view, expectedWidth, scale, 1200, 720, {
                                        view === expectedView && view.width == expectedWidth && view.height == expectedHeight
                                    }) { outcome ->
                                        outcome.onSuccess { applied -> if (applied) fits.incrementAndGet() }
                                            .onFailure { lastScaleError = it.toString(); scaleFailures.incrementAndGet() }
                                    }
                                }
                            } else {
                                applier.cancel()
                                view.settings.useWideViewPort = false
                                policy.reset()
                            }
                        }
                    }),
                    "YahagiPresentation",
                )
            }
            action(script)
        } finally {
            instrumentation.runOnMainSync { applier.cancel(); if (::view.isInitialized) view.destroy() }
        }
    }

    private fun load(url: String, body: String) {
        val loaded = CountDownLatch(1)
        instrumentation.runOnMainSync {
            policy.reset()
            applier.cancel()
            view.settings.useWideViewPort = false
            view.setInitialScale(0)
            view.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    pageFinishes.incrementAndGet()
                    loaded.countDown()
                }
            }
            view.loadDataWithBaseURL(
                url,
                "<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>html,body{margin:0}iframe,embed{max-width:100%}</style></head><body>$body</body></html>",
                "text/html", "UTF-8", null,
            )
        }
        assertTrue("Local document loads", loaded.await(15, TimeUnit.SECONDS))
    }

    private fun eval(script: String): String {
        val complete = CountDownLatch(1)
        var result = "null"
        instrumentation.runOnMainSync {
            view.evaluateJavascript(script) { value -> result = value; complete.countDown() }
        }
        assertTrue("JS callback returned", complete.await(10, TimeUnit.SECONDS))
        return result
    }

    private fun settle() { Thread.sleep(300); instrumentation.waitForIdleSync() }

    private fun fit(script: String, allowFailure: Boolean = false) {
        val before = fits.get()
        val failuresBefore = scaleFailures.get()
        eval(script)
        val deadline = android.os.SystemClock.uptimeMillis() + 5_500
        while (fits.get() <= before && scaleFailures.get() == failuresBefore &&
            android.os.SystemClock.uptimeMillis() < deadline) {
            Thread.sleep(50)
        }
        assertTrue("Native fit callback completes", fits.get() > before || scaleFailures.get() > failuresBefore)
        if (!allowFailure) assertEquals("Native fit completes without error: $lastScaleError", failuresBefore, scaleFailures.get())
    }

    private fun applyAndWait(current: Boolean = true): Result<Boolean> {
        val completed = CountDownLatch(1)
        var outcome: Result<Boolean>? = null
        instrumentation.runOnMainSync {
            applier.apply(view, view.width, 50, 1200, 720, { current }) { result -> outcome = result; completed.countDown() }
        }
        assertTrue("Native helper completes", completed.await(6, TimeUnit.SECONDS))
        return checkNotNull(outcome)
    }

    private fun assertCanvasCorners() {
        var width = 0
        var height = 0
        instrumentation.runOnMainSync { width = view.width; height = view.height }
        val targetScale = minOf(width / 1200.0, height / 720.0)
        fun readMetrics() = JSONObject(eval("""
            (()=>{const r=document.querySelector('canvas').getBoundingClientRect(),v=visualViewport;
            return {x:r.x-v.offsetLeft,y:r.y-v.offsetTop,right:r.right-v.offsetLeft,bottom:r.bottom-v.offsetTop,width:r.width,height:r.height,visualWidth:v.width,visualScale:v.scale,dpr:devicePixelRatio};})()
        """.trimIndent()))
        var metrics = readMetrics()
        val deadline = android.os.SystemClock.uptimeMillis() + 2_000
        while (kotlin.math.abs(metrics.getDouble("visualScale") * metrics.getDouble("dpr") - targetScale) > 0.5 / 1200.0 &&
            android.os.SystemClock.uptimeMillis() < deadline) {
            Thread.sleep(50)
            metrics = readMetrics()
        }
        val scale = metrics.getDouble("visualScale") * metrics.getDouble("dpr")
        assertEquals("Canvas CSS width is preserved", 1200.0, metrics.getDouble("width"), 0.01)
        assertEquals("Canvas CSS height is preserved", 720.0, metrics.getDouble("height"), 0.01)
        assertEquals("Exact proportional fit is applied at ${width}x$height", targetScale, scale, 0.5 / 1200.0)
        assertEquals("Left edge is aligned", 0.0, metrics.getDouble("x") * scale, 0.5)
        assertEquals("Top edge is aligned", 0.0, metrics.getDouble("y") * scale, 0.5)
        assertEquals("Right edge has no rounding gap", 1200 * targetScale, metrics.getDouble("right") * scale, 0.5)
        assertEquals("Bottom edge has no rounding gap", 720 * targetScale, metrics.getDouble("bottom") * scale, 0.5)
        assertTrue("Right corner is visible", metrics.getDouble("right") * scale <= width + 0.5)
        assertTrue("Bottom corner is visible", metrics.getDouble("bottom") * scale <= height + 0.5)
    }

    private fun assertCanvasRemainsFitted() {
        assertCanvasCorners()
        Thread.sleep(150)
        assertCanvasCorners()
        Thread.sleep(350)
        assertCanvasCorners()
    }

    private class FailingScaleWebView(context: Context) : WebView(context) {
        var failNextScale = false
        var scaleSetterCalls = 0
        var zoomCalls = 0
        val nativeScaleCalls get() = scaleSetterCalls + zoomCalls
        override fun zoomBy(zoomFactor: Float) {
            zoomCalls++
            if (failNextScale) {
                failNextScale = false
                throw IllegalStateException("Intentional zoomBy failure")
            }
            super.zoomBy(zoomFactor)
        }
        override fun setInitialScale(scaleInPercent: Int) {
            scaleSetterCalls++
            if (failNextScale) {
                failNextScale = false
                throw IllegalStateException("Intentional setInitialScale failure")
            }
            super.setInitialScale(scaleInPercent)
        }
    }
}
