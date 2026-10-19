package app.yahagi.kancollebrowser.browser

import org.junit.Assert.*
import org.junit.Test

class GameModApplyCoordinatorTest {
    @Test fun waitsForVerifiedDispatchBeforeChangingActiveResources() {
        val harness = Harness()
        harness.coordinator.apply(true) { harness.result = it }
        assertEquals(0, harness.applied)
        harness.prepare!!()
        assertEquals(1, harness.applied)
        harness.complete!!("reloaded", true)
        assertEquals(1, harness.finished)
        assertEquals(0, harness.rolledBack)
        assertEquals("reloaded", harness.result)
    }

    @Test fun probeFailureLeavesOldSessionAndDraftUntouched() {
        val harness = Harness()
        harness.coordinator.apply(true) { harness.result = it }
        harness.complete!!("blocked", false)
        assertEquals(0, harness.applied)
        assertEquals("blocked", harness.result)
    }

    @Test fun dispatchFailureAfterPreparationRestoresPreviousSession() {
        val harness = Harness()
        harness.coordinator.apply(true) { harness.result = it }
        harness.prepare!!()
        harness.complete!!("failed", false)
        assertEquals(1, harness.rolledBack)
        assertEquals(0, harness.finished)
    }

    @Test fun deliveredReloadFailureDoesNotPretendTheOldPageWasRestored() {
        val harness = Harness()
        harness.coordinator.apply(true) { harness.result = it }
        harness.prepare!!()
        harness.complete!!("blocked", true)
        assertEquals(1, harness.finished)
        assertEquals(0, harness.rolledBack)
        assertEquals("blocked", harness.result)
    }

    @Test fun noGamePersistsNextLaunchConfigurationWithoutInventingReload() {
        val harness = Harness()
        harness.coordinator.apply(false) { harness.result = it }
        assertEquals(1, harness.applied)
        assertEquals(1, harness.finished)
        assertNull(harness.prepare)
        assertEquals("noGame", harness.result)
    }

    @Test fun rejectsConcurrentApplyAndIgnoresLateDuplicateCompletion() {
        val harness = Harness()
        harness.coordinator.apply(true) { harness.result = it }
        var second: String? = null
        harness.coordinator.apply(true) { second = it }
        assertEquals("blocked", second)
        harness.prepare!!()
        harness.complete!!("reloaded", true)
        harness.complete!!("failed", false)
        assertEquals(1, harness.finished)
        assertEquals(0, harness.rolledBack)
        assertEquals("reloaded", harness.result)
    }

    private class Harness {
        var applied = 0
        var finished = 0
        var rolledBack = 0
        var result: String? = null
        var prepare: (() -> Unit)? = null
        var complete: ((String, Boolean) -> Unit)? = null
        val coordinator = GameModApplyCoordinator(
            applyConfig = { ++applied },
            rollback = { rolledBack++ },
            finish = { finished++ },
            requestReload = { before, done -> prepare = before; complete = done },
        )
    }
}
