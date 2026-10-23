package app.yahagi.kancollebrowser.browser

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GameFrameRateReplyRegistryTest {
    @Test fun twoReadyDocumentsAtOneOriginBothReceiveLifecycleChanges() {
        val registry = GameFrameRateReplyRegistry<Proxy>()
        val current = Proxy()
        val late = Proxy()
        registry.registerReady("game", current)
        registry.registerReady("game", late)
        registry.broadcast { it.received++ }
        assertEquals(1, current.received)
        assertEquals(1, late.received)
    }

    @Test fun tenThousandDuplicateReadyMessagesDoNotGrowTheRegistry() {
        val registry = GameFrameRateReplyRegistry<Proxy>()
        val current = Proxy()
        repeat(10_000) { registry.registerReady("game", current) }
        assertEquals(1, registry.size)
        registry.broadcast { it.received++ }
        assertEquals(1, current.received)
    }

    @Test fun readyFloodCannotEvictTheDocumentProducingValidSamples() {
        val registry = GameFrameRateReplyRegistry<Proxy>()
        val current = Proxy()
        registry.registerReady("game", current)
        assertTrue(registry.recordSample("game", current))
        repeat(10_000) { registry.registerReady("game", Proxy()) }
        assertTrue(registry.size <= 8)
        assertTrue(registry.contains("game", current))
        registry.broadcast { it.received++ }
        assertEquals(1, current.received)
    }

    @Test fun thousandsOfReloadsKeepTheLatestDocumentRegisteredAndTotalStateBounded() {
        val registry = GameFrameRateReplyRegistry<Proxy>()
        repeat(10_000) { index ->
            val current = Proxy()
            val origin = "frame-${index % 5}"
            registry.registerReady(origin, current)
            assertTrue(registry.recordSample(origin, current))
            assertTrue(registry.contains(origin, current))
            assertTrue(registry.size <= 32)
        }
        println("REPLY_REGISTRY_STRESS reloads=10000 readyFlood=10000 duplicateReady=10000")
    }

    @Test fun sampleWithoutReadyCannotRegisterAControlChannel() {
        val registry = GameFrameRateReplyRegistry<Proxy>()
        val stranger = Proxy()
        assertFalse(registry.recordSample("game", stranger))
        assertFalse(registry.contains("game", stranger))
        assertEquals(0, registry.size)
    }

    @Test fun failedDeliveryRemovesOnlyTheFailedProxy() {
        val registry = GameFrameRateReplyRegistry<Proxy>()
        val failing = Proxy()
        val current = Proxy()
        registry.registerReady("game", failing)
        registry.registerReady("game", current)
        registry.broadcast { if (it === failing) throw IllegalStateException("gone") else it.received++ }
        assertFalse(registry.contains("game", failing))
        assertTrue(registry.contains("game", current))
        assertEquals(1, current.received)
    }

    @Test fun identityDeduplicationDoesNotTrustProxyEqualsOrHashCode() {
        val registry = GameFrameRateReplyRegistry<Proxy>()
        val one = Proxy()
        val two = Proxy()
        registry.registerReady("game", one)
        registry.registerReady("game", two)
        assertEquals(2, registry.size)
        registry.remove("game", one)
        assertTrue(registry.contains("game", two))
        assertFalse(registry.contains("game", one))
    }

    @Test fun clearingDuringDispatchDoesNotDeliverToRemovedDocuments() {
        val registry = GameFrameRateReplyRegistry<Proxy>()
        registry.registerReady("game", Proxy())
        val later = Proxy()
        registry.registerReady("game", later)
        var deliveries = 0
        registry.broadcast { deliveries++; registry.clear() }
        assertEquals(1, deliveries)
        assertEquals(0, later.received)
        assertEquals(0, registry.size)
    }

    private class Proxy {
        var received = 0
        override fun equals(other: Any?) = other is Proxy
        override fun hashCode() = 1
    }
}
