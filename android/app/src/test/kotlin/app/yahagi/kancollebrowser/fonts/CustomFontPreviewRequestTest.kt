package app.yahagi.kancollebrowser.fonts

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class CustomFontPreviewRequestTest {
    private fun arguments() = mapOf<String, Any>(
        "id" to "a".repeat(64), "text" to "矢矧\n0123456789\nAa Bb",
        "width" to 640, "fontSize" to 36.0, "locale" to "ja", "color" to 0xddccbbaaL.toInt(),
    )

    @Test fun `accepts bounded input in physical pixels with an ARGB color`() {
        val request = CustomFontPreviewRequest.fromArguments(arguments())
        assertEquals("a".repeat(64), request.id)
        assertEquals(640, request.width)
        assertEquals(36f, request.fontSize)
        assertEquals("ja", request.locale)
        assertEquals(0xddccbbaaL.toInt(), request.color)
        assertEquals(512, request.bitmapHeight(Int.MAX_VALUE))
    }

    @Test fun `accepts all supported locales and exact numeric limits`() {
        for (locale in listOf("zh", "zh-Hant", "ja", "ko", "en")) {
            val request = CustomFontPreviewRequest.fromArguments(arguments() + mapOf(
                "text" to "x".repeat(512), "width" to 1024, "fontSize" to 72.0,
                "locale" to locale, "color" to 0xffffffffL,
            ))
            assertEquals(-1, request.color)
            assertEquals(512, request.bitmapHeight(10000))
            assertTrue(request.width.toLong() * request.bitmapHeight(10000) <= 524288)
        }
        assertEquals(12f, CustomFontPreviewRequest.fromArguments(arguments() + mapOf("width" to 160, "fontSize" to 12.0)).fontSize)
    }

    @Test fun `rejects missing or incorrectly typed arguments before rendering`() {
        for (value in listOf(null, "bad", 1, emptyMap<String, Any>())) invalid { CustomFontPreviewRequest.fromArguments(value) }
        for ((field, badValues) in mapOf(
            "id" to listOf<Any>("../font", "A".repeat(64), 7),
            "text" to listOf<Any>(true, "", "x".repeat(513)),
            "width" to listOf<Any>(159, 1025, 640.5, 640.0, "640"),
            "fontSize" to listOf<Any>(11.99, 72.01, Double.NaN, Double.POSITIVE_INFINITY, 36, "36"),
            "locale" to listOf<Any>("fr", "zh-TW", 1),
            "color" to listOf<Any>(0x100000000L, -2147483649L, 1.0, "white"),
        )) {
            invalid { CustomFontPreviewRequest.fromArguments(arguments() - field) }
            for (bad in badValues) invalid { CustomFontPreviewRequest.fromArguments(arguments() + (field to bad)) }
        }
    }

    @Test fun `rejects impossible layout dimensions before allocating a bitmap`() {
        val request = CustomFontPreviewRequest.fromArguments(arguments())
        assertEquals(1, request.bitmapHeight(1))
        assertEquals(120, request.bitmapHeight(120))
        invalid { request.bitmapHeight(0) }
        invalid { request.bitmapHeight(-1) }
    }

    @Test fun `limits PNG output during writes rather than after allocation`() {
        val output = CustomFontPreviewOutput(8)
        output.write(byteArrayOf(1, 2, 3), 0, 3)
        repeat(5) { output.write(it) }
        assertEquals(8, output.toByteArray().size)
        invalid { output.write(0) }
        invalid { output.write(byteArrayOf(1, 2), 0, 2) }
        assertEquals(8, output.toByteArray().size)
    }

    @Test fun `admits one preview until the previous reply has completed`() {
        val gate = CustomFontPreviewGate()
        assertTrue(gate.tryAcquire())
        assertFalse(gate.tryAcquire())
        gate.release()
        assertTrue(gate.tryAcquire())
        gate.release()
    }

    @Test fun `simultaneous preview submissions cannot grow the worker queue`() {
        val gate = CustomFontPreviewGate()
        val start = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(8)
        try {
            val results = (1..24).map { pool.submit<Boolean> { start.await(); gate.tryAcquire() } }
            start.countDown()
            assertEquals(1, results.count { it.get(5, TimeUnit.SECONDS) })
        } finally { pool.shutdownNow() }
    }

    private fun invalid(block: () -> Unit) {
        try { block(); fail("Expected a bounded preview operation to fail") }
        catch (error: CustomFontException) { assertEquals("invalid_preview", error.code) }
    }
}
