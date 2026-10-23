package app.yahagi.kancollebrowser.browser

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.webkit.WebView
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** Applies a fixed-canvas fit on the UI thread, including repeated fits at the same percent. */
internal class FixedCanvasScaleApplier {
    private val handler = Handler(Looper.getMainLooper())
    private var latestRequest = 0L
    private var cancelPending: (() -> Unit)? = null

    fun cancel() {
        latestRequest++
        val pending = cancelPending
        cancelPending = null
        pending?.invoke()
    }

    fun apply(
        webView: WebView,
        viewportWidth: Int,
        scalePercent: Int,
        contentWidth: Int,
        contentHeight: Int,
        isCurrent: () -> Boolean,
        onComplete: (Result<Boolean>) -> Unit,
    ) {
        cancel()
        val request = latestRequest
        var completed = false
        var timeout: Runnable? = null
        var alignment: Runnable? = null
        fun finish(outcome: Result<Boolean>) {
            if (completed) return
            completed = true
            timeout?.let(handler::removeCallbacks)
            alignment?.let(handler::removeCallbacks)
            if (request == latestRequest) cancelPending = null
            onComplete(outcome)
        }
        cancelPending = { finish(Result.success(false)) }
        try {
            val viewportHeight = webView.height
            require(viewportWidth > 0 && viewportHeight > 0 && scalePercent > 0 && contentWidth > 0 && contentHeight > 0)
            val targetScale = min(
                viewportWidth.toDouble() / contentWidth,
                viewportHeight.toDouble() / contentHeight,
            )
            val documentUrl = webView.url
            fun current() = !completed && request == latestRequest && isCurrent() && webView.url == documentUrl
            if (!current()) {
                finish(Result.success(false))
                return
            }
            val timeoutAction = Runnable {
                val outcome = try {
                    if (!current()) Result.success(false)
                    else Result.failure(IllegalStateException("Game fitting timed out."))
                } catch (error: RuntimeException) {
                    Result.failure<Boolean>(error)
                }
                finish(outcome)
            }
            timeout = timeoutAction
            if (!handler.postDelayed(timeoutAction, 5_000L)) {
                finish(Result.success(false))
                return
            }

            var observedScale: Double? = null
            var stableSamples = 0
            var scaleBeforeZoom: Double? = null
            var zoomRequestedAt = 0L
            var targetStableSince: Long? = null
            var scrollResetPending = false
            fun alignPrecisely() {
                try {
                    if (!current()) {
                        finish(Result.success(false))
                        return
                    }
                    // Read renderer geometry rather than WebView.getScale(), whose
                    // UI-thread cache can still describe the preceding page scale.
                    webView.evaluateJavascript("""
                        (() => {
                          if (window.__yahagiMobileReadPresentation?.() !== 'game') return null;
                          const viewport = window.visualViewport;
                          return viewport ? {scale: viewport.scale * window.devicePixelRatio, x: viewport.offsetLeft, y: viewport.offsetTop} : null;
                        })();
                    """.trimIndent()) { value ->
                        try {
                            if (!current() || value == "null") {
                                finish(Result.success(false))
                                return@evaluateJavascript
                            }
                            val viewport = JSONObject(value)
                            val actualScale = viewport.getDouble("scale")
                            check(actualScale.isFinite() && actualScale > 0) { "Invalid game viewport scale." }
                            val scaleError = abs(targetScale - actualScale) * max(contentWidth, contentHeight)
                            val offsetX = abs(viewport.getDouble("x")) * actualScale
                            val offsetY = abs(viewport.getDouble("y")) * actualScale
                            val offset = max(offsetX, offsetY)
                            val previous = observedScale
                            stableSamples = if (previous != null &&
                                abs(previous - actualScale) * max(contentWidth, contentHeight) <= 0.05
                            ) stableSamples + 1 else 1
                            observedScale = actualScale
                            val now = SystemClock.uptimeMillis()
                            val pendingScale = scaleBeforeZoom
                            if (pendingScale != null && stableSamples >= 3 &&
                                (abs(pendingScale - actualScale) * max(contentWidth, contentHeight) > 0.05 ||
                                    now - zoomRequestedAt >= 250L)
                            ) scaleBeforeZoom = null
                            // Chromium's minimum zoom can round by a fraction of
                            // a physical pixel. Do not retry an unresolvable subpixel.
                            if (scaleError <= 0.25 && offset <= 0.25 && stableSamples >= 3) {
                                val stableSince = targetStableSince ?: now.also { targetStableSince = it }
                                if (now - stableSince >= 160L && now - zoomRequestedAt >= 500L) {
                                    webView.scrollTo(0, 0)
                                    finish(Result.success(true))
                                    return@evaluateJavascript
                                }
                            } else {
                                targetStableSince = null
                                if (scaleError > 0.25 && stableSamples >= 3 && scaleBeforeZoom == null) {
                                    // Use one zoom path only. Mixing initial-scale
                                    // settings with zoomBy lets late renderer updates
                                    // overwrite a fit that appeared to have completed.
                                    scaleBeforeZoom = actualScale
                                    zoomRequestedAt = now
                                    webView.zoomBy((targetScale / actualScale).toFloat().coerceIn(0.01f, 100f))
                                    observedScale = null
                                    stableSamples = 0
                                }
                            }
                            if (scrollResetPending) {
                                webView.scrollTo(0, 0)
                                scrollResetPending = false
                            } else if (scaleError <= 0.25 && offset > 0.25 && stableSamples >= 3) {
                                // Native scroll positions are integers. A leftover
                                // fractional renderer offset can round to zero, so
                                // scrollTo(0, 0) alone never sends a new position.
                                // Move one pixel, then return on the next sample.
                                webView.scrollTo(if (offsetX > 0.25) 1 else 0, if (offsetY > 0.25) 1 else 0)
                                scrollResetPending = true
                            } else {
                                webView.scrollTo(0, 0)
                            }
                            val retry = Runnable { alignPrecisely() }
                            alignment = retry
                            if (!handler.postDelayed(retry, 32L)) finish(Result.success(false))
                        } catch (error: Exception) {
                            finish(Result.failure(error as? RuntimeException
                                ?: IllegalStateException("Unable to read game viewport.", error)))
                        }
                    }
                } catch (error: RuntimeException) {
                    finish(Result.failure(error))
                }
            }

            // Chromium rounds its viewport in density-independent pixels before
            // applying the document-width zoom limit. Reserve that rounding plus
            // one DIP so the exact fit remains above the minimum allowed zoom.
            val density = webView.resources.displayMetrics.density.toDouble()
            val roundedViewportWidth = ceil(viewportWidth / density) * density
            val minimumWidth = max(
                contentWidth.toDouble(),
                ceil((roundedViewportWidth + density) * 100.0 / scalePercent) + 1.0,
            ).toLong()
            val prepare = """
                (() => {
                  const style = document.getElementById('__yahagi_mobile_fixed_canvas__');
                  if (!style || window.__yahagiMobileReadPresentation?.() !== 'game') return false;
                  const rule = style.sheet?.cssRules[0];
                  if (rule?.selectorText !== 'html, body') return false;
                  // CSSOM edits preserve textContent, so runtime reinjection
                  // keeps this rule. Removing the game style releases it.
                  rule.style.setProperty('min-width', '${minimumWidth}px', 'important');
                  // Independent physical edge rounding can leave a subpixel
                  // contain margin. Keep the DMM shell outside the game clipped.
                  rule.style.setProperty('background', '#000', 'important');
                  const sheet = style.sheet;
                  let bodyRule = Array.from(sheet.cssRules).find((entry) => entry.selectorText === 'body');
                  if (!bodyRule) bodyRule = sheet.cssRules[sheet.insertRule('body {}', sheet.cssRules.length)];
                  bodyRule.style.setProperty('clip-path', 'polygon(0 0, ${contentWidth}px 0, ${contentWidth}px ${contentHeight}px, 0 ${contentHeight}px)', 'important');
                  return true;
                })();
            """.trimIndent()
            webView.evaluateJavascript(prepare) { prepared ->
                if (!handler.post {
                    try {
                        if (!current() || prepared != "true") {
                            finish(Result.success(false))
                        } else {
                            alignPrecisely()
                        }
                    } catch (error: RuntimeException) {
                        finish(Result.failure(error))
                    }
                }) {
                    finish(Result.success(false))
                }
            }
        } catch (error: RuntimeException) {
            finish(Result.failure(error))
        }
    }
}
