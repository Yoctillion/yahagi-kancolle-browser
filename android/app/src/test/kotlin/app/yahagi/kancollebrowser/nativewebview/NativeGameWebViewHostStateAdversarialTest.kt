package app.yahagi.kancollebrowser.nativewebview

import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeGameWebViewHostStateAdversarialTest {
    @Test
    fun millionHostEventsRejectStaleRendererAndVisibilityGenerations() {
        var creations = 0
        repeat(1_000) { seed ->
            val random = Random(seed)
            val state = NativeGameWebViewHostState()
            var lastCreated = -1L
            repeat(1_000) { step ->
                val beforePhase = state.phase
                val beforeGeneration = state.generationId
                when (random.nextInt(5)) {
                    0 -> if (beforePhase == NativeGameWebViewHostPhase.ABSENT) {
                        val created = state.beginCreate()
                        assertTrue("seed=$seed step=$step", created > lastCreated)
                        lastCreated = created
                        creations++
                    } else {
                        assertTrue(runCatching { state.beginCreate() }.exceptionOrNull() is IllegalStateException)
                        assertEquals(beforePhase, state.phase)
                        assertEquals(beforeGeneration, state.generationId)
                    }
                    1 -> beforeGeneration?.let(state::markReady)
                    2 -> beforeGeneration?.let(state::beginDestroy)
                    3 -> beforeGeneration?.let(state::completeDestroy)
                    else -> {
                        val foreign = when (random.nextInt(4)) {
                            0 -> -1L
                            1 -> lastCreated - 1
                            2 -> lastCreated + 1
                            else -> Long.MAX_VALUE
                        }
                        if (foreign != beforeGeneration) {
                            assertFalse(state.accepts(foreign))
                            assertFalse(state.markReady(foreign))
                            assertFalse(state.beginDestroy(foreign))
                            assertFalse(state.completeDestroy(foreign))
                            assertEquals(beforePhase, state.phase)
                            assertEquals(beforeGeneration, state.generationId)
                        }
                    }
                }
                val current = state.generationId
                assertEquals(state.phase == NativeGameWebViewHostPhase.ABSENT, current == null)
                if (current != null) {
                    assertEquals(lastCreated, current)
                    assertEquals(
                        state.phase == NativeGameWebViewHostPhase.CREATING ||
                            state.phase == NativeGameWebViewHostPhase.READY,
                        state.accepts(current),
                    )
                }
                if (lastCreated > 0L) assertFalse(state.accepts(lastCreated - 1))
            }
        }
        assertTrue(creations > 10_000)
        println("HOST_STATE_STRESS seeds=1000 operations=1000000 creations=$creations")
    }
}
