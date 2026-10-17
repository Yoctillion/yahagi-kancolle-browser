package app.yahagi.kancollebrowser.browser

import org.json.JSONObject

internal data class GameFramePerformanceSample(
    val fps: Double?,
    val rafFps: Double?,
    val renderFps: Double?,
    val renderP95Ms: Double?,
    val renderP99Ms: Double?,
    val renderCpuP95Ms: Double?,
    val pixiVersion: String?,
    val configuredFps: Double?,
    val target: String,
    val visible: Boolean,
    val sampleDurationMs: Double,
    val renderFrames: Int?,
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "fps" to fps,
        "rafFps" to rafFps,
        "renderFps" to renderFps,
        "renderP95Ms" to renderP95Ms,
        "renderP99Ms" to renderP99Ms,
        "renderCpuP95Ms" to renderCpuP95Ms,
        "pixiVersion" to pixiVersion,
        "configuredFps" to configuredFps,
        "target" to target,
        "visible" to visible,
        "sampleDurationMs" to sampleDurationMs,
        "renderFrames" to renderFrames,
    )

    fun isUsableForAuto(expectedTarget: String): Boolean {
        val expectedFps = when (expectedTarget) {
            "fps30" -> 30.0
            "fps60" -> 60.0
            else -> return false
        }
        return visible && target == expectedTarget && fps != null &&
            configuredFps != null && configuredFps + 0.001 >= expectedFps
    }

    companion object {
        private val numericKeys = listOf(
            "fps", "rafFps", "renderFps", "renderP95Ms", "renderP99Ms",
            "renderCpuP95Ms", "configuredFps", "sampleDurationMs", "renderFrames",
        )

        fun fromJson(json: JSONObject): GameFramePerformanceSample? {
            for (key in numericKeys) {
                if (json.isNull(key)) continue
                val value = (json.opt(key) as? Number)?.toDouble() ?: return null
                if (!value.isFinite() || value < 0) return null
            }
            val target = json.opt("target") as? String ?: return null
            if (target != "fps30" && target != "fps60" && target != "highRefresh") return null
            val visible = json.opt("visible") as? Boolean ?: return null
            val duration = json.optionalNumber("sampleDurationMs") ?: return null
            if (duration <= 0) return null
            val frameCount = json.optionalNumber("renderFrames")
            if (frameCount != null &&
                (frameCount > Int.MAX_VALUE || frameCount != frameCount.toInt().toDouble())
            ) return null
            if (!json.isNull("pixiVersion") && json.opt("pixiVersion") !is String) return null

            return GameFramePerformanceSample(
                fps = json.optionalNumber("fps"),
                rafFps = json.optionalNumber("rafFps"),
                renderFps = json.optionalNumber("renderFps"),
                renderP95Ms = json.optionalNumber("renderP95Ms"),
                renderP99Ms = json.optionalNumber("renderP99Ms"),
                renderCpuP95Ms = json.optionalNumber("renderCpuP95Ms"),
                pixiVersion = json.opt("pixiVersion") as? String,
                configuredFps = json.optionalNumber("configuredFps"),
                target = target,
                visible = visible,
                sampleDurationMs = duration,
                renderFrames = frameCount?.toInt(),
            )
        }

        private fun JSONObject.optionalNumber(key: String): Double? =
            (opt(key) as? Number)?.toDouble()
    }
}
