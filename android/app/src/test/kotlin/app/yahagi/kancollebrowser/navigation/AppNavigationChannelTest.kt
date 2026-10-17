package app.yahagi.kancollebrowser.navigation

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppNavigationChannelTest {
    @Test
    fun moveToBackgroundMovesTheTaskOnceAndReturnsTrue() {
        var moves = 0
        val channel = AppNavigationChannel {
            moves += 1
            true
        }
        val result = RecordingNavigationResult()

        channel.onMethodCall(MethodCall("moveToBackground", null), result)

        assertEquals(1, moves)
        assertEquals(true, result.successValue)
        assertEquals(1, result.replyCount)
        assertNull(result.errorCode)
    }

    @Test
    fun moveToBackgroundReturnsFalseWhenAndroidDoesNotMoveTheTask() {
        var moves = 0
        val channel = AppNavigationChannel {
            moves += 1
            false
        }
        val result = RecordingNavigationResult()

        channel.onMethodCall(MethodCall("moveToBackground", null), result)

        assertEquals(1, moves)
        assertEquals(false, result.successValue)
        assertEquals(1, result.replyCount)
        assertNull(result.errorCode)
    }

    @Test
    fun unsupportedMethodDoesNotMoveTheTask() {
        var moves = 0
        val channel = AppNavigationChannel {
            moves += 1
            true
        }
        val result = RecordingNavigationResult()

        channel.onMethodCall(MethodCall("unknown", null), result)

        assertEquals(0, moves)
        assertTrue(result.notImplemented)
        assertEquals(1, result.replyCount)
        assertNull(result.errorCode)
    }

    @Test
    fun androidFailureRepliesWithAnErrorWithoutTryingAgain() {
        var moves = 0
        val channel = AppNavigationChannel {
            moves += 1
            throw IllegalStateException("Activity task is unavailable")
        }
        val result = RecordingNavigationResult()

        channel.onMethodCall(MethodCall("moveToBackground", null), result)

        assertEquals(1, moves)
        assertEquals("move_to_background_failed", result.errorCode)
        assertEquals(1, result.replyCount)
        assertNull(result.successValue)
    }
}

private class RecordingNavigationResult : MethodChannel.Result {
    var successValue: Any? = null
    var errorCode: String? = null
    var notImplemented = false
    var replyCount = 0

    override fun success(result: Any?) {
        replyCount += 1
        successValue = result
    }

    override fun error(code: String, message: String?, details: Any?) {
        replyCount += 1
        errorCode = code
    }

    override fun notImplemented() {
        replyCount += 1
        notImplemented = true
    }
}
