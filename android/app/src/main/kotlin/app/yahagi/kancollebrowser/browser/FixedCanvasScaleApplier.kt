package app.yahagi.kancollebrowser.browser

import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import kotlin.math.ceil
import kotlin.math.max

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
        isCurrent: () -> Boolean,
        onComplete: (Result<Boolean>) -> Unit,
    ) {
        cancel()
        val request = latestRequest
        var completed = false
        var timeout: Runnable? = null
        fun finish(outcome: Result<Boolean>) {
            if (completed) return
            completed = true
            timeout?.let(handler::removeCallbacks)
            if (request == latestRequest) cancelPending = null
            onComplete(outcome)
        }
        cancelPending = { finish(Result.success(false)) }
        try {
            require(viewportWidth > 0 && scalePercent > 0 && contentWidth > 0)
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

            // Chromium clamps page scale to its document-width minimum. Allow
            // the requested integer percent even when physical edges rounded
            // the outer 5:3 slot by a pixel. The game itself stays 1200x720.
            val minimumWidth = max(
                contentWidth.toDouble(),
                ceil(viewportWidth * 100.0 / scalePercent) + 1.0,
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
                  return true;
                })();
            """.trimIndent()
            webView.evaluateJavascript(prepare) { prepared ->
                if (!handler.post {
                    val applied = try {
                        if (!current() || prepared != "true") {
                            Result.success(false)
                        } else {
                            // AwSettings and Blink both deduplicate identical
                            // initial-scale values, even after effective zoom moved.
                            webView.setInitialScale(0)
                            webView.setInitialScale(scalePercent)
                            null
                        }
                    } catch (error: RuntimeException) {
                        Result.failure<Boolean>(error)
                    }
                    if (applied != null) {
                        finish(applied)
                    } else if (!handler.post {
                        val aligned = try {
                            if (!current()) Result.success(false)
                            else {
                                webView.scrollTo(0, 0)
                                Result.success(true)
                            }
                        } catch (error: RuntimeException) {
                            Result.failure<Boolean>(error)
                        }
                        finish(aligned)
                    }) {
                        finish(Result.success(false))
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
