package app.yahagi.kancollebrowser.browser

import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class GadgetBypassEngineTest {
    private lateinit var server: TestHttpServer
    private lateinit var tempDir: File

    @Before
    fun setUp() {
        server = TestHttpServer()
        server.start()
        tempDir = Files.createTempDirectory("gadget-engine-test").toFile()
    }

    @After
    fun tearDown() {
        server.stop()
    }

    private fun baseUrl() = "http://127.0.0.1:${server.port}"

    private fun installEndpointHandler(bytes: ByteArray, status: Int = 200) {
        server.handlers["/endpoint"] = Pair({ bytes }, status)
    }

    private fun installDirectHandler(bytes: ByteArray, status: Int = 200) {
        server.handlers["/gadget_html5"] = Pair({ bytes }, status)
    }

    private fun engine(
        cache: GadgetBypassCache = GadgetBypassCache(tempDir, now = { 1000L }),
        endpointValidator: (String) -> Boolean = { true },
    ) = GadgetBypassEngine(
        cache = cache,
        connectTimeoutMs = 3000,
        readTimeoutMs = 3000,
        endpointValidator = endpointValidator,
    )

    private fun originalUrl(path: String = "/gadget_html5/js/kcs_cda.js") =
        "http://w00g.kancolle-server.com$path"

    @Test
    fun fetchesFromEndpointWhenItSucceeds() {
        val content = "window.__gadget = true;".toByteArray(StandardCharsets.UTF_8)
        installEndpointHandler(content)
        val result = engine().fetch(
            originalUrl = originalUrl(),
            endpoint = "${baseUrl()}/endpoint",
        )
        assertArrayEquals(content, result)
        assertEquals(1, server.hits["/endpoint"])
        assertNull(server.hits["/gadget_html5"])
    }

    @Test
    fun returnsNullForWebViewFallbackWhenEndpointFails() {
        installEndpointHandler(ByteArray(0), status = 500)
        val result = engine().fetch(
            originalUrl = originalUrl(),
            endpoint = "${baseUrl()}/endpoint",
        )
        assertNull(result)
        assertEquals(1, server.hits["/endpoint"])
        assertNull(server.hits["/gadget_html5"])
    }

    @Test
    fun returnsNullWhenBothSourcesFail() {
        installEndpointHandler(ByteArray(0), status = 404)
        installDirectHandler(ByteArray(0), status = 500)
        assertNull(
            engine().fetch(
                originalUrl = originalUrl(),
                endpoint = "${baseUrl()}/endpoint",
            ),
        )
    }

    @Test
    fun servesSecondCallFromCacheWithoutHittingNetwork() {
        val content = "cached content".toByteArray(StandardCharsets.UTF_8)
        installEndpointHandler(content)
        val engine = engine()
        val url = originalUrl()
        val endpoint = "${baseUrl()}/endpoint"
        assertArrayEquals(content, engine.fetch(url, endpoint))
        assertArrayEquals(content, engine.fetch(url, endpoint))
        assertEquals(1, server.hits["/endpoint"])
    }

    @Test
    fun isolatesCachedFilesByEndpoint() {
        server.handlers["/endpoint-a"] = Pair({ "from-a".toByteArray() }, 200)
        server.handlers["/endpoint-b"] = Pair({ "from-b".toByteArray() }, 200)
        val engine = engine()
        val url = originalUrl()

        assertArrayEquals(
            "from-a".toByteArray(),
            engine.fetch(url, "${baseUrl()}/endpoint-a"),
        )
        assertArrayEquals(
            "from-b".toByteArray(),
            engine.fetch(url, "${baseUrl()}/endpoint-b"),
        )
        assertEquals(1, server.hits["/endpoint-a"])
        assertEquals(1, server.hits["/endpoint-b"])
    }

    @Test
    fun ignoresRequestsOutsideBypassRules() {
        installEndpointHandler(ByteArray(0))
        assertNull(
            engine().fetch(
                originalUrl = "http://203.104.209.7/kcsapi/api_start2/getData",
                endpoint = "${baseUrl()}/endpoint",
            ),
        )
        assertNull(server.hits["/endpoint"])
    }

    @Test
    fun rejectsHtmlErrorBodyEvenWhenScriptMimeIsClaimed() {
        installEndpointHandler("<!doctype html><html><body>temporarily unavailable</body></html>".toByteArray())
        server.responseHeaders["/endpoint"] = mapOf("Content-Type" to "application/javascript")
        val cache = GadgetBypassCache(tempDir, now = { 1000L })
        val endpoint = "${baseUrl()}/endpoint"
        assertNull(engine(cache).fetch(originalUrl(), endpoint))
        assertEquals(0L, cache.sizeBytes())
    }

    @Test
    fun rejectsHtmlErrorBodyWithLeadingCommentsAndClaimedScriptMime() {
        installEndpointHandler("\uFEFF \n<!-- gateway error -->\n<!-- retry later -->\n<!DOCTYPE html><html><body>unavailable</body></html>".toByteArray())
        server.responseHeaders["/endpoint"] = mapOf("Content-Type" to "application/javascript")
        val cache = GadgetBypassCache(tempDir, now = { 1000L })
        assertNull(engine(cache).fetch(originalUrl(), "${baseUrl()}/endpoint"))
        assertEquals(0L, cache.sizeBytes())
    }

    @Test
    fun rejectsIncompatibleMimeAndEmptyScript() {
        installEndpointHandler("window.ready=true;".toByteArray())
        server.responseHeaders["/endpoint"] = mapOf("Content-Type" to "image/png")
        assertNull(engine().fetch(originalUrl(), "${baseUrl()}/endpoint"))
        installEndpointHandler(ByteArray(0))
        server.responseHeaders["/endpoint"] = mapOf("Content-Type" to "application/javascript")
        assertNull(engine().fetch(originalUrl(), "${baseUrl()}/endpoint"))
    }

    @Test
    fun invalidLegacyCachedScriptIsNotReused() {
        val cache = GadgetBypassCache(tempDir, now = { 1000L })
        val endpoint = "${baseUrl()}/endpoint"
        cache.put("$endpoint\n${originalUrl()}", "<html>failed</html>".toByteArray())
        installEndpointHandler("window.ready=true;".toByteArray())
        assertArrayEquals("window.ready=true;".toByteArray(), engine(cache).fetch(originalUrl(), endpoint))
        assertEquals(1, server.hits["/endpoint"])
    }

    @Test
    fun concurrentSameUrlRequestsShareOneMirrorAttempt() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val content = "window.ready=true;".toByteArray()
        server.handlers["/endpoint"] = Pair({ entered.countDown(); release.await(2, TimeUnit.SECONDS); content }, 200)
        val engine = engine()
        val executor = Executors.newFixedThreadPool(4)
        try {
            val first = executor.submit<ByteArray?> { engine.fetch(originalUrl(), "${baseUrl()}/endpoint") }
            org.junit.Assert.assertTrue(entered.await(2, TimeUnit.SECONDS))
            val others = (1..3).map { executor.submit<ByteArray?> { engine.fetch(originalUrl(), "${baseUrl()}/endpoint") } }
            Thread.sleep(100)
            release.countDown()
            (listOf(first) + others).forEach { assertArrayEquals(content, it.get(2, TimeUnit.SECONDS)) }
            assertEquals(1, server.hits["/endpoint"])
        } finally { release.countDown(); executor.shutdownNow() }
    }

    @Test
    fun repeatedFailureFallsBackWithoutAnotherMirrorAttempt() {
        installEndpointHandler(ByteArray(0), status = 500)
        val engine = engine()
        repeat(3) { assertNull(engine.fetch(originalUrl(), "${baseUrl()}/endpoint")) }
        assertEquals(1, server.hits["/endpoint"])
    }

    @Test
    fun mirrorWaitHasTotalBudgetAndLateSuccessCannotEnterCache() {
        server.handlers["/endpoint"] = Pair({ Thread.sleep(300); "window.ready=true;".toByteArray() }, 200)
        val cache = GadgetBypassCache(tempDir, now = { 1000L })
        val engine = GadgetBypassEngine(cache, connectTimeoutMs = 3000, readTimeoutMs = 3000,
            totalTimeoutMs = 80, endpointValidator = { true })
        val started = System.nanoTime()
        assertNull(engine.fetch(originalUrl(), "${baseUrl()}/endpoint"))
        assertTrue(TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started) < 500)
        Thread.sleep(350)
        assertEquals(0L, cache.sizeBytes())
    }

    @Test
    fun truncatedMirrorBodyNeverEntersCache() {
        installEndpointHandler("window.ready=true;".toByteArray())
        server.responseHeaders["/endpoint"] = mapOf("Content-Type" to "text/javascript", "Content-Length" to "1000")
        val cache = GadgetBypassCache(tempDir, now = { 1000L })
        assertNull(engine(cache).fetch(originalUrl(), "${baseUrl()}/endpoint"))
        assertEquals(0L, cache.sizeBytes())
    }

    @Test
    fun clearDuringMirrorDownloadDoesNotRepopulateCache() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val body = "window.ready=true;".toByteArray()
        server.handlers["/endpoint"] = Pair({ entered.countDown(); release.await(2, TimeUnit.SECONDS); body }, 200)
        val cache = GadgetBypassCache(tempDir, now = { 1000L })
        val engine = engine(cache)
        val executor = Executors.newSingleThreadExecutor()
        try {
            val request = executor.submit<ByteArray?> { engine.fetch(originalUrl(), "${baseUrl()}/endpoint") }
            assertTrue(entered.await(2, TimeUnit.SECONDS))
            cache.clear()
            release.countDown()
            assertArrayEquals(body, request.get(2, TimeUnit.SECONDS))
            assertEquals(0L, cache.sizeBytes())
        } finally { release.countDown(); executor.shutdownNow() }
    }

    @Test
    fun failedMirrorCanRetryAfterShortCooldown() {
        var now = 0L
        installEndpointHandler(ByteArray(0), status = 500)
        val engine = GadgetBypassEngine(GadgetBypassCache(tempDir), endpointValidator = { true },
            failureCooldownMs = 50, nanoTime = { now })
        val endpoint = "${baseUrl()}/endpoint"
        assertNull(engine.fetch(originalUrl(), endpoint))
        assertNull(engine.fetch(originalUrl(), endpoint))
        assertEquals(1, server.hits["/endpoint"])
        now = TimeUnit.MILLISECONDS.toNanos(51)
        installEndpointHandler("window.ready=true;".toByteArray())
        assertArrayEquals("window.ready=true;".toByteArray(), engine.fetch(originalUrl(), endpoint))
        assertEquals(2, server.hits["/endpoint"])
    }
}
