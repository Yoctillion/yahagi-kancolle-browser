package app.yahagi.kancollebrowser.browser

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.yahagi.kancollebrowser.mods.GameModRepository
import app.yahagi.kancollebrowser.mods.toWebResourceResponse
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Exercise Chromium's actual image loading and both the mod and ordinary cache paths. */
@RunWith(AndroidJUnit4::class)
class GameModWebViewTest {
    @Test fun importedPngOverridesCacheAndResetRestoresOriginalPixels() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val root = File(context.cacheDir, "game-mod-webview-${System.nanoTime()}")
        val mod = png(Color.RED)
        val original = png(Color.BLUE)
        val repo = GameModRepository(File(root, "mods"))
        val zip = ByteArrayOutputStream().also { bytes ->
            ZipOutputStream(bytes).use { stream ->
                stream.putNextEntry(ZipEntry("cache/kcs2/img/mod-probe.hack.png"))
                stream.write(mod)
                stream.closeEntry()
            }
        }.toByteArray()
        val preflight = repo.preflight(ByteArrayInputStream(zip), "cache.zip")
        repo.commitImport(preflight["token"] as String)
        @Suppress("UNCHECKED_CAST")
        val entry = (repo.status()["packages"] as List<Map<String, Any?>>).single()
        @Suppress("UNCHECKED_CAST")
        val resource = (entry["resources"] as List<Map<String, Any?>>).single()
        repo.saveDraft(mapOf("master" to true, "order" to listOf(entry["id"]),
            "enabledPackages" to listOf(entry["id"]), "enabledResources" to listOf(resource["id"])))
        repo.finishApply(repo.applyDraft())
        val fetches = AtomicInteger()
        val cacheRoot = File(root, "ordinary-cache")
        val cache = GameResourceCacheEngine(
            GameResourceCacheStore(cacheRoot, GameResourceCacheIndex(File(cacheRoot, "index.json")), 10_000),
            GameResourceFetcher { _, _, _ ->
                fetches.incrementAndGet()
                GameResourceFetchResult(200, "OK", mapOf("Content-Type" to "image/png"), original)
            },
        ) { GameResourceCacheMode.LIGHT }
        var webView: WebView? = null
        try {
            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                webView = WebView(context).apply {
                    settings.javaScriptEnabled = true
                    webViewClient = GadgetBypassWebViewClient(
                        WebViewClient(), GadgetBypassEngine(GadgetBypassCache(File(root, "bypass"))),
                        { false }, { GadgetBypassRules.DEFAULT_ENDPOINT }, cache, true,
                        modResourceInterceptor = { url, method, headers ->
                            repo.openResource(url, method, headers)?.toWebResourceResponse()
                        },
                    )
                }
            }
            assertEquals("255,0,0,255", loadPixel(checkNotNull(webView), "mod"))
            assertEquals(0, fetches.get())
            assertTrue((repo.status()["hits"] as List<*>).contains(resource["id"]))
            repo.resetAll()
            repo.finishApply(repo.applyDraft())
            assertEquals("0,0,255,255", loadPixel(checkNotNull(webView), "reset"))
            assertEquals(1, fetches.get())
            assertTrue((repo.status()["packages"] as List<*>).isEmpty())
            assertTrue(cacheRoot.exists())
        } finally {
            InstrumentationRegistry.getInstrumentation().runOnMainSync { webView?.destroy() }
            root.deleteRecursively()
        }
    }

    private fun png(color: Int): ByteArray = ByteArrayOutputStream().use { output ->
        val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(color)
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
        bitmap.recycle()
        output.toByteArray()
    }

    private fun loadPixel(webView: WebView, version: String): String {
        val probe = PixelProbe()
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            webView.addJavascriptInterface(probe, "PixelProbe")
            webView.loadDataWithBaseURL("https://w15p.kancolle-server.com/", """
                <html><body><script>
                const image = new Image();
                image.onload = () => {
                  try {
                    const canvas = document.createElement('canvas');
                    canvas.width = canvas.height = 2;
                    const ctx = canvas.getContext('2d');
                    ctx.drawImage(image, 0, 0);
                    PixelProbe.report(Array.from(ctx.getImageData(0, 0, 1, 1).data).join(','));
                  } catch (error) { PixelProbe.report(String(error)); }
                };
                image.onerror = () => PixelProbe.report('image-error');
                image.src = '/kcs2/img/mod-probe.png?version=$version';
                document.body.appendChild(image);
                </script></body></html>
            """.trimIndent(), "text/html", "UTF-8", null)
        }
        assertTrue("Chromium did not finish the image request", probe.done.await(20, TimeUnit.SECONDS))
        return checkNotNull(probe.value)
    }

    class PixelProbe {
        val done = CountDownLatch(1)
        @Volatile var value: String? = null
        @JavascriptInterface fun report(result: String) { value = result; done.countDown() }
    }
}
