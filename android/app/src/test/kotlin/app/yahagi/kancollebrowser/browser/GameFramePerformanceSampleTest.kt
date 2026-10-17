package app.yahagi.kancollebrowser.browser

import java.math.BigDecimal
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GameFramePerformanceSampleTest {
    @Test
    fun `parses complete sample without changing metric units`() {
        val sample = requireNotNull(GameFramePerformanceSample.fromJson(payload()))

        assertEquals(59.5, sample.fps!!, 0.001)
        assertEquals(120.0, sample.rafFps!!, 0.001)
        assertEquals(90.0, sample.renderFps!!, 0.001)
        assertEquals(15.0, sample.renderP95Ms!!, 0.001)
        assertEquals(21.0, sample.renderP99Ms!!, 0.001)
        assertEquals(2.5, sample.renderCpuP95Ms!!, 0.001)
        assertEquals("4.8.9", sample.pixiVersion)
        assertEquals(60.0, sample.configuredFps!!, 0.001)
        assertEquals(1000.0, sample.sampleDurationMs, 0.001)
        assertEquals(90, sample.renderFrames)
        assertEquals("fps60", sample.target)
        assertTrue(sample.visible)
        assertTrue(sample.isUsableForAuto("fps60"))
    }

    @Test
    fun `exports fixed schema and preserves unavailable measurements as null`() {
        val json = payload()
        for (key in nullableNumbers + "renderFrames" + "pixiVersion") {
            json.put(key, JSONObject.NULL)
        }
        val sample = requireNotNull(GameFramePerformanceSample.fromJson(json))
        val exported = sample.toMap()

        assertEquals(
            setOf("fps", "rafFps", "renderFps", "renderP95Ms", "renderP99Ms",
                "renderCpuP95Ms", "pixiVersion", "configuredFps", "target", "visible",
                "sampleDurationMs", "renderFrames"),
            exported.keys,
        )
        for (key in nullableNumbers + "renderFrames" + "pixiVersion") {
            assertTrue(exported.containsKey(key))
            assertNull(exported[key])
        }
        assertEquals("fps60", exported["target"])
        assertEquals(true, exported["visible"])
        assertEquals(1000.0, exported["sampleDurationMs"])
        assertFalse(sample.isUsableForAuto("fps60"))
    }

    @Test
    fun `rejects negative non numeric and non finite timing or fps fields`() {
        for (key in nullableNumbers + "sampleDurationMs") {
            for (invalid in listOf(-1.0, "60", "NaN", "Infinity", BigDecimal("1e10000"), true)) {
                assertNull("$key = $invalid", GameFramePerformanceSample.fromJson(payload().put(key, invalid)))
            }
        }
    }

    @Test
    fun `requires positive duration and explicit boolean visibility and valid target`() {
        for (key in listOf("target", "visible", "sampleDurationMs")) {
            val missing = payload().apply { remove(key) }
            assertNull("missing $key", GameFramePerformanceSample.fromJson(missing))
            assertNull("null $key", GameFramePerformanceSample.fromJson(payload().put(key, JSONObject.NULL)))
        }
        assertNull(GameFramePerformanceSample.fromJson(payload().put("sampleDurationMs", 0)))
        assertNull(GameFramePerformanceSample.fromJson(payload().put("visible", "true")))
        for (invalid in listOf("fps120", "", "AUTO", 60)) {
            assertNull(GameFramePerformanceSample.fromJson(payload().put("target", invalid)))
        }
        for (target in listOf("fps30", "fps60", "highRefresh")) {
            assertNotNull(GameFramePerformanceSample.fromJson(payload().put("target", target)))
        }
    }

    @Test
    fun `requires render frame counts to be nonnegative bounded integers`() {
        for (invalid in listOf(-1, 1.5, "90", 2_147_483_648L, true)) {
            assertNull(GameFramePerformanceSample.fromJson(payload().put("renderFrames", invalid)))
        }
        assertEquals(0, GameFramePerformanceSample.fromJson(payload().put("renderFrames", 0))?.renderFrames)
    }

    @Test
    fun `valid zero fps is usable but paused stale or low cap samples are excluded from auto`() {
        val sample = requireNotNull(GameFramePerformanceSample.fromJson(payload()))
        assertTrue(sample.copy(fps = 0.0).isUsableForAuto("fps60"))
        assertFalse(sample.copy(visible = false).isUsableForAuto("fps60"))
        assertFalse(sample.isUsableForAuto("fps30"))
        assertFalse(sample.copy(configuredFps = 15.0).isUsableForAuto("fps60"))
        assertFalse(sample.copy(configuredFps = null).isUsableForAuto("fps60"))
        assertFalse(sample.copy(fps = null).isUsableForAuto("fps60"))
        assertTrue(sample.copy(target = "fps30", configuredFps = 30.0).isUsableForAuto("fps30"))
        assertFalse(sample.copy(target = "fps30", configuredFps = 15.0).isUsableForAuto("fps30"))
        assertFalse(sample.copy(target = "highRefresh").isUsableForAuto("highRefresh"))
    }

    @Test
    fun `does not coerce invalid PIXI version into a string`() {
        assertNull(GameFramePerformanceSample.fromJson(payload().put("pixiVersion", 4)))
    }

    private fun payload(): JSONObject = JSONObject()
        .put("fps", 59.5)
        .put("rafFps", 120.0)
        .put("renderFps", 90.0)
        .put("renderP95Ms", 15.0)
        .put("renderP99Ms", 21.0)
        .put("renderCpuP95Ms", 2.5)
        .put("pixiVersion", "4.8.9")
        .put("configuredFps", 60.0)
        .put("target", "fps60")
        .put("visible", true)
        .put("sampleDurationMs", 1000.0)
        .put("renderFrames", 90)

    private val nullableNumbers = listOf(
        "fps", "rafFps", "renderFps", "renderP95Ms", "renderP99Ms", "renderCpuP95Ms", "configuredFps",
    )
}
