package app.yahagi.kancollebrowser.display

import android.os.Build
import android.view.RoundedCorner
import android.view.WindowInsets
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class DisplayCornerChannel(
    private val rootWindowInsets: () -> WindowInsets?,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val METHOD_CHANNEL_NAME = "app.yahagi.kancollebrowser/display_corners"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "getRoundedCorners") {
            result.notImplemented()
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(null)
            return
        }
        val insets = rootWindowInsets()
        if (insets == null) {
            result.success(null)
            return
        }
        result.success(
            mapOf(
                "topLeft" to insets.radiusOf(RoundedCorner.POSITION_TOP_LEFT),
                "topRight" to insets.radiusOf(RoundedCorner.POSITION_TOP_RIGHT),
                "bottomLeft" to insets.radiusOf(RoundedCorner.POSITION_BOTTOM_LEFT),
                "bottomRight" to insets.radiusOf(RoundedCorner.POSITION_BOTTOM_RIGHT),
            ),
        )
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun WindowInsets.radiusOf(position: Int): Int? =
        getRoundedCorner(position)?.radius
}
