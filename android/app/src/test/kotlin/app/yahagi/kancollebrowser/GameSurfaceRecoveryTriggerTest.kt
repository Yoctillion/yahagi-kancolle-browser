package app.yahagi.kancollebrowser

import org.junit.Assert.assertEquals
import org.junit.Test

class GameSurfaceRecoveryTriggerTest {
    @Test
    fun initialAndRepeatedResumeDoNotRequestRecovery() {
        val reasons = mutableListOf<GameSurfaceRecoveryReason>()
        val trigger = GameSurfaceRecoveryTrigger(reasons::add)

        trigger.onResume()
        trigger.onResume()

        assertEquals(emptyList<GameSurfaceRecoveryReason>(), reasons)
    }

    @Test
    fun pausedActivityRequestsRecoveryOnlyOnceWhenResumed() {
        val reasons = mutableListOf<GameSurfaceRecoveryReason>()
        val trigger = GameSurfaceRecoveryTrigger(reasons::add)

        trigger.onPause()
        trigger.onPause()
        trigger.onResume()
        trigger.onResume()

        assertEquals(listOf(GameSurfaceRecoveryReason.ACTIVITY_RESUMED), reasons)
    }

    @Test
    fun eachLaterPauseResumeCycleRequestsAnotherRecovery() {
        val reasons = mutableListOf<GameSurfaceRecoveryReason>()
        val trigger = GameSurfaceRecoveryTrigger(reasons::add)

        trigger.onPause()
        trigger.onResume()
        trigger.onPause()
        trigger.onResume()

        assertEquals(
            listOf(GameSurfaceRecoveryReason.ACTIVITY_RESUMED, GameSurfaceRecoveryReason.ACTIVITY_RESUMED),
            reasons,
        )
    }

    @Test
    fun configurationRecoveryDoesNotConsumePendingActivityResume() {
        val reasons = mutableListOf<GameSurfaceRecoveryReason>()
        val trigger = GameSurfaceRecoveryTrigger(reasons::add)

        trigger.onPause()
        trigger.onConfigurationChanged()
        trigger.onResume()

        assertEquals(
            listOf(GameSurfaceRecoveryReason.CONFIGURATION_CHANGED, GameSurfaceRecoveryReason.ACTIVITY_RESUMED),
            reasons,
        )
    }

    @Test
    fun windowModeTransitionsRequestSurfaceRecovery() {
        val reasons = mutableListOf<GameSurfaceRecoveryReason>()
        val trigger = GameSurfaceRecoveryTrigger(reasons::add)

        trigger.onMultiWindowModeChanged(true)
        trigger.onMultiWindowModeChanged(false)
        trigger.onPictureInPictureModeChanged(true)
        trigger.onPictureInPictureModeChanged(false)

        assertEquals(
            listOf(
                GameSurfaceRecoveryReason.MULTI_WINDOW_ENTER,
                GameSurfaceRecoveryReason.MULTI_WINDOW_EXIT,
                GameSurfaceRecoveryReason.PICTURE_IN_PICTURE_ENTER,
                GameSurfaceRecoveryReason.PICTURE_IN_PICTURE_EXIT,
            ),
            reasons,
        )
    }

    @Test
    fun configurationChangesRequestSurfaceRecovery() {
        val reasons = mutableListOf<GameSurfaceRecoveryReason>()
        val trigger = GameSurfaceRecoveryTrigger(reasons::add)

        trigger.onConfigurationChanged()

        assertEquals(
            listOf(GameSurfaceRecoveryReason.CONFIGURATION_CHANGED),
            reasons,
        )
    }
}
