package app.yahagi.kancollebrowser.browser

import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

enum class GameFrameRateMode(val wireName: String) {
    AUTO("auto"),
    STABLE_60("stable60"),
    STABLE_30("stable30"),
    HIGH_REFRESH("highRefresh");

    companion object {
        fun fromWireName(value: String?): GameFrameRateMode =
            entries.firstOrNull { it.wireName == value } ?: AUTO
    }
}

class GameFrameRateManager(
    private val bridge: GameFrameRateBridge,
    private val systemConstraints: GameFrameRateSystemConstraintSource,
) : MethodChannel.MethodCallHandler {
    @Volatile
    var mode: GameFrameRateMode = GameFrameRateMode.AUTO
        private set
    private var configured = false
    private var requestedTarget = GameFrameRateTarget.FPS_60

    init {
        systemConstraints.start(::onSystemStateChanged)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && bridge.isSupported(),
            )
            "configure" -> {
                val requestedMode = GameFrameRateMode.fromWireName(
                    call.argument<String>("mode"),
                )
                try {
                    val initialTarget = requestedMode.initialTarget
                    bridge.configure(
                        GameFrameRateSystemPolicy.effectiveTarget(
                            requestedMode,
                            initialTarget,
                            systemConstraints.state,
                        ),
                    )
                    requestedTarget = initialTarget
                    mode = requestedMode
                    configured = true
                    result.success(null)
                } catch (error: GameFrameRateBridgeException) {
                    result.error(error.code, error.message, null)
                }
            }
            "applyTarget" -> {
                val target = GameFrameRateTarget.fromWireName(
                    call.argument<String>("target"),
                )
                if (target == null) {
                    result.error("invalid_frame_rate_target", "Unknown frame-rate target.", null)
                } else {
                    requestedTarget = target
                    bridge.apply(effectiveTarget())
                    result.success(null)
                }
            }
            "measuredFps" -> result.success(
                GameFrameRateSystemPolicy.runtimeSample(
                    mode,
                    systemConstraints.state,
                    bridge.measuredFps(),
                ),
            )
            "performanceSnapshot" -> result.success(
                bridge.performanceSnapshot() + mapOf(
                    "mode" to mode.wireName,
                    "requestedTarget" to requestedTarget.wireName,
                    "effectiveTarget" to effectiveTarget().wireName,
                    "powerSave" to systemConstraints.state.powerSaveEnabled,
                    "thermalStatus" to systemConstraints.state.thermalStatus,
                ),
            )
            "setLayerMode" -> {
                if (bridge.setLayerMode(call.argument<String>("mode") ?: "")) {
                    result.success(bridge.performanceSnapshot())
                } else {
                    result.error("invalid_layer_mode", "No game WebView or unknown layer mode.", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun setForeground(foreground: Boolean) {
        bridge.setForeground(foreground)
    }

    fun dispose() {
        systemConstraints.dispose()
        bridge.dispose()
        configured = false
        mode = GameFrameRateMode.AUTO
        requestedTarget = GameFrameRateTarget.FPS_60
    }

    private fun onSystemStateChanged(@Suppress("UNUSED_PARAMETER") state: GameFrameRateSystemState) {
        if (configured) bridge.apply(effectiveTarget())
    }

    private fun effectiveTarget(): GameFrameRateTarget =
        GameFrameRateSystemPolicy.effectiveTarget(
            mode,
            requestedTarget,
            systemConstraints.state,
        )
}

private val GameFrameRateMode.initialTarget: GameFrameRateTarget
    get() = when (this) {
        GameFrameRateMode.STABLE_30 -> GameFrameRateTarget.FPS_30
        GameFrameRateMode.AUTO,
        GameFrameRateMode.STABLE_60 -> GameFrameRateTarget.FPS_60
        GameFrameRateMode.HIGH_REFRESH -> GameFrameRateTarget.HIGH_REFRESH
    }
