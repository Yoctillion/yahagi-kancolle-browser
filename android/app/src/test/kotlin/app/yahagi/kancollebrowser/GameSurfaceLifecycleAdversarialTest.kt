package app.yahagi.kancollebrowser

import org.junit.Assert.assertEquals
import org.junit.Test

class GameSurfaceLifecycleAdversarialTest {
    @Test
    fun everySixEventLifecycleAndWindowSequencePreservesResumeBoundaries() {
        val alphabet = 7
        val length = 6
        val sequenceCount = 117_649 // 7^6, including repeated pause/resume and window events.
        repeat(sequenceCount) { encoded ->
            var remainder = encoded
            val events = IntArray(length) {
                (remainder % alphabet).also { remainder /= alphabet }
            }
            val actual = mutableListOf<GameSurfaceRecoveryReason>()
            val expected = mutableListOf<GameSurfaceRecoveryReason>()
            val trigger = GameSurfaceRecoveryTrigger(actual::add)
            for (index in events.indices) {
                when (events[index]) {
                    0 -> trigger.onPause()
                    1 -> {
                        trigger.onResume()
                        // Only a pause newer than every earlier resume creates a new boundary.
                        val lastPause = (0 until index).lastOrNull { events[it] == 0 } ?: -1
                        val lastResume = (0 until index).lastOrNull { events[it] == 1 } ?: -1
                        if (lastPause > lastResume) expected += GameSurfaceRecoveryReason.ACTIVITY_RESUMED
                    }
                    2 -> {
                        trigger.onConfigurationChanged()
                        expected += GameSurfaceRecoveryReason.CONFIGURATION_CHANGED
                    }
                    3 -> {
                        trigger.onMultiWindowModeChanged(true)
                        expected += GameSurfaceRecoveryReason.MULTI_WINDOW_ENTER
                    }
                    4 -> {
                        trigger.onMultiWindowModeChanged(false)
                        expected += GameSurfaceRecoveryReason.MULTI_WINDOW_EXIT
                    }
                    5 -> {
                        trigger.onPictureInPictureModeChanged(true)
                        expected += GameSurfaceRecoveryReason.PICTURE_IN_PICTURE_ENTER
                    }
                    else -> {
                        trigger.onPictureInPictureModeChanged(false)
                        expected += GameSurfaceRecoveryReason.PICTURE_IN_PICTURE_EXIT
                    }
                }
            }
            assertEquals("lifecycle sequence ${events.joinToString()}", expected, actual)
        }
        println("LIFECYCLE_EXHAUSTIVE sequences=$sequenceCount operations=${sequenceCount * length}")
    }

    @Test
    fun resumeCallbackReentryCannotDuplicateTheSameRecovery() {
        var recoveries = 0
        lateinit var trigger: GameSurfaceRecoveryTrigger
        trigger = GameSurfaceRecoveryTrigger {
            recoveries++
            trigger.onResume()
        }
        repeat(10_000) {
            trigger.onPause()
            trigger.onResume()
            trigger.onResume()
        }
        assertEquals(10_000, recoveries)
        println("LIFECYCLE_REENTRY cycles=10000")
    }
}
