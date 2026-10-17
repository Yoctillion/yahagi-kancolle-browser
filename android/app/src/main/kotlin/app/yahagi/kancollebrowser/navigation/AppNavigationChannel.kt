package app.yahagi.kancollebrowser.navigation

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class AppNavigationChannel(
    private val moveTaskToBackground: () -> Boolean,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val METHOD_CHANNEL_NAME = "app.yahagi.kancollebrowser/app_navigation"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "moveToBackground") {
            result.notImplemented()
            return
        }

        val moved = try {
            moveTaskToBackground()
        } catch (_: RuntimeException) {
            result.error(
                "move_to_background_failed",
                "Unable to move the app to the background.",
                null,
            )
            return
        }
        result.success(moved)
    }
}
