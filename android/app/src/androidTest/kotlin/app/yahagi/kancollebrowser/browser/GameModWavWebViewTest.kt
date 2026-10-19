package app.yahagi.kancollebrowser.browser

import android.content.Context
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
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
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Uses an isolated repository and never changes the user's mod configuration. */
@RunWith(AndroidJUnit4::class)
class GameModWavWebViewTest {
    @Test fun wavReplacesMp3RequestAndChromiumDecodesItsActualFormat() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        for (bits in listOf(8, 16, 24, 32)) {
            checkVoice(context, generatedWav(bits), "pcm$bits", 0.1, 1)
        }
        checkVoice(context, generatedWav(32, true), "float32", 0.1, 1)
        InstrumentationRegistry.getArguments().getString("wavFixture")?.let { name ->
            val source = File(context.cacheDir, name).canonicalFile
            require(source.parentFile == context.cacheDir.canonicalFile && source.isFile)
            checkVoice(context, source.readBytes(), "real-extensible-float32", 3.11, 2)
        }
    }

    private fun checkVoice(context: Context, bytes: ByteArray, label: String, duration: Double, channels: Int) {
        val root = File(context.cacheDir, "game-mod-wav-webview-${System.nanoTime()}")
        require(root.canonicalFile.parentFile == context.cacheDir.canonicalFile)
        var webView: WebView? = null
        try {
            val repo = GameModRepository(File(root, "mods"))
            val archive = ByteArrayOutputStream().also { output ->
                ZipOutputStream(output).use { zip ->
                    zip.putNextEntry(ZipEntry("cache/kcs/sound/kcwavprobe/123456.hack.wav"))
                    zip.write(bytes)
                    zip.closeEntry()
                }
            }.toByteArray()
            val preview = repo.preflight(ByteArrayInputStream(archive), "wav-probe.zip")
            assertEquals(1, preview["supportedCount"])
            val entry = repo.commitImport(preview["token"] as String)
            val resource = (entry["resources"] as List<*>).single() as Map<*, *>
            assertEquals("kcs/sound/kcwavprobe/123456.mp3", resource["path"])
            repo.saveDraft(mapOf("master" to true, "order" to listOf(entry["id"]),
                "enabledPackages" to listOf(entry["id"]), "enabledResources" to listOf(resource["id"])))
            repo.finishApply(repo.applyDraft())
            val fallbacks = AtomicInteger()
            val probe = AudioProbe()
            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                webView = WebView(context).apply {
                    settings.javaScriptEnabled = true
                    settings.mediaPlaybackRequiresUserGesture = false
                    addJavascriptInterface(probe, "AudioProbe")
                    val fallback = object : WebViewClient() {
                        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                            // loadDataWithBaseURL supplies the main document itself.
                            if (request.isForMainFrame || request.url.scheme in listOf("data", "about")) return null
                            if (request.url.path?.startsWith("/kcs/sound/") == true) fallbacks.incrementAndGet()
                            return WebResourceResponse("text/plain", "UTF-8", 404, "Not Found",
                                emptyMap(), ByteArrayInputStream(byteArrayOf()))
                        }
                    }
                    webViewClient = GadgetBypassWebViewClient(
                        fallback, GadgetBypassEngine(GadgetBypassCache(File(root, "bypass"))),
                        { false }, { GadgetBypassRules.DEFAULT_ENDPOINT },
                        modResourceInterceptor = { url, method, headers ->
                            repo.openResource(url, method, headers)?.toWebResourceResponse()
                        },
                    )
                    loadDataWithBaseURL("https://w15p.kancolle-server.com/", """
                        <html><body><script>
                        (async () => {
                          let context, audio;
                          try {
                            AudioProbe.progress('script-started');
                            const url = '/kcs/sound/kcwavprobe/123456.mp3?version=wav';
                            const head = await fetch(url, {method:'HEAD'});
                            AudioProbe.progress('head-complete');
                            const range = await fetch(url, {headers:{Range:'bytes=0-15'}});
                            const prefix = new Uint8Array(await range.arrayBuffer());
                            AudioProbe.progress('range-complete');
                            const response = await fetch(url);
                            const data = await response.arrayBuffer();
                            AudioProbe.progress('body-complete');
                            const byteLength = data.byteLength;
                            context = new AudioContext();
                            const decoded = await context.decodeAudioData(data);
                            AudioProbe.progress('web-audio-decoded');
                            let peak = 0;
                            for (const value of decoded.getChannelData(0)) peak = Math.max(peak, Math.abs(value));
                            audio = new Audio();
                            audio.preload = 'metadata';
                            audio.muted = true;
                            const mediaDuration = await new Promise((resolve,reject) => {
                              audio.onloadedmetadata = () => resolve(audio.duration);
                              audio.onerror = () => reject(Error('HTML audio error '+audio.error?.code));
                              audio.src = url;
                              audio.load();
                            });
                            AudioProbe.report(JSON.stringify({head:head.status, range:range.status,
                              prefix:Array.from(prefix.slice(0,4)), bytes:byteLength,
                              mime:response.headers.get('Content-Type'), duration:decoded.duration,
                              channels:decoded.numberOfChannels, sampleRate:decoded.sampleRate,
                              peak, mediaDuration}));
                          } catch(error) { AudioProbe.report(JSON.stringify({error:String(error)})); }
                          finally {
                            if(audio) { audio.removeAttribute('src'); audio.load(); }
                            if(context) context.close();
                          }
                        })();
                        </script></body></html>
                    """.trimIndent(), "text/html", "UTF-8", null)
                }
            }
            val completed = probe.done.await(30, TimeUnit.SECONDS)
            assertTrue("Chromium did not decode $label; last stage=${probe.stage}; fallbacks=${fallbacks.get()}", completed)
            val result = JSONObject(checkNotNull(probe.value))
            assertFalse(result.toString(), result.has("error"))
            assertEquals("audio/wav", result.getString("mime"))
            assertEquals(200, result.getInt("head"))
            assertEquals(206, result.getInt("range"))
            assertEquals("[82,73,70,70]", result.getJSONArray("prefix").toString())
            assertEquals(bytes.size, result.getInt("bytes"))
            assertEquals(duration, result.getDouble("duration"), 0.002)
            assertEquals(duration, result.getDouble("mediaDuration"), 0.002)
            assertEquals(channels, result.getInt("channels"))
            assertTrue(result.getDouble("peak") > 0.01)
            assertEquals(0, fallbacks.get())
            assertTrue((repo.status()["hits"] as List<*>).contains(resource["id"]))
            InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
                putString("wav_case", label)
                putString("wav_probe", result.toString())
            })
        } finally {
            InstrumentationRegistry.getInstrumentation().runOnMainSync { webView?.destroy() }
            if (root.exists()) root.deleteRecursively()
        }
    }

    private fun generatedWav(bits: Int, floating: Boolean = false): ByteArray {
        val frames = 4800
        val stride = bits / 8
        val headerBytes = if (floating) 58 else 44
        return ByteBuffer.allocate(headerBytes + frames * stride).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray(Charsets.US_ASCII)); putInt(capacity() - 8)
            put("WAVEfmt ".toByteArray(Charsets.US_ASCII)); putInt(if (floating) 18 else 16)
            putShort((if (floating) 3 else 1).toShort()); putShort(1)
            putInt(48000); putInt(48000 * stride); putShort(stride.toShort()); putShort((stride * 8).toShort())
            if (floating) {
                putShort(0)
                put("fact".toByteArray(Charsets.US_ASCII)); putInt(4); putInt(frames)
            }
            put("data".toByteArray(Charsets.US_ASCII)); putInt(frames * stride)
            repeat(frames) { frame ->
                val sample = 0.25 * kotlin.math.sin(2 * Math.PI * 440 * frame / 48000)
                when {
                    floating -> putFloat(sample.toFloat())
                    bits == 8 -> put((sample * 127 + 128).toInt().toByte())
                    bits == 16 -> putShort((sample * 32767).toInt().toShort())
                    bits == 24 -> {
                        val value = (sample * 8388607).toInt()
                        repeat(3) { index -> put((value ushr (index * 8)).toByte()) }
                    }
                    bits == 32 -> putInt((sample * Int.MAX_VALUE).toInt())
                }
            }
        }.array()
    }

    class AudioProbe {
        val done = CountDownLatch(1)
        @Volatile var value: String? = null
        @Volatile var stage: String = "created"
        @JavascriptInterface fun progress(result: String) { stage = result }
        @JavascriptInterface fun report(result: String) { value = result; done.countDown() }
    }
}
