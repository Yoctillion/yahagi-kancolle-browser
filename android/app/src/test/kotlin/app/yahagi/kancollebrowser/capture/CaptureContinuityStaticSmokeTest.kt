package app.yahagi.kancollebrowser.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.util.ArrayDeque
import java.util.concurrent.Executor

class CaptureContinuityStaticSmokeTest {
    @Test
    fun oversizedStringResponseNotifiesWithoutExposingTheDroppedBody() {
        val fixture = Fixture()

        fixture.dispatcher.submit(stringMessage("private-body".repeat(200)), "https://game")
        fixture.runAll()

        fixture.assertSingleInterruption()
    }

    @Test
    fun oversizedBinaryResponseNotifiesWithoutExposingTheDroppedBody() {
        val fixture = Fixture()

        fixture.dispatcher.submit(binaryMessage("private-body".repeat(200)), "https://game")
        fixture.runAll()

        fixture.assertSingleInterruption()
    }

    @Test
    fun malformedMessagesNotifyForBothProtocols() {
        val fixture = Fixture()

        fixture.dispatcher.submit("invalid private-body", "https://game")
        fixture.dispatcher.submit(byteArrayOf(0, 0, 0), "https://game")
        fixture.runAll()

        assertEquals(listOf(interruption(), interruption()), fixture.delivered)
    }

    @Test
    fun rejectionNotificationPreservesItsPlaceBetweenValidResponses() {
        val fixture = Fixture()

        fixture.dispatcher.submit(stringMessage("before"), "https://game")
        fixture.dispatcher.submit("invalid private-body", "https://game")
        fixture.dispatcher.submit(binaryMessage("after"), "https://game")
        fixture.worker.runAll()

        assertTrue(fixture.delivered.isEmpty())
        fixture.main.runAll()
        assertEquals(
            listOf("kcsapi_response", "capture_interrupted", "kcsapi_response"),
            fixture.delivered.map { it["kind"] },
        )
        assertEquals(interruption(), fixture.delivered[1])
    }

    @Test
    fun retiredGenerationCannotInterruptOrDeliverQueuedResponses() {
        val fixture = Fixture()
        val retiredGeneration = fixture.dispatcher.currentGeneration
        fixture.dispatcher.submit("invalid private-body", "https://game", retiredGeneration)
        fixture.dispatcher.submit(stringMessage("retired"), "https://game", retiredGeneration)
        fixture.dispatcher.invalidatePending()
        fixture.dispatcher.submit(byteArrayOf(0, 0, 0), "https://game", retiredGeneration)
        fixture.dispatcher.submit(stringMessage("current"), "https://game")
        fixture.runAll()

        assertEquals(listOf("kcsapi_response"), fixture.delivered.map { it["kind"] })
        assertEquals("current", fixture.delivered.single()["responseBody"])
    }

    @Test
    fun invalidationDropsAlreadyPostedRejectionNotification() {
        val fixture = Fixture()
        fixture.dispatcher.submit("invalid private-body", "https://game")
        fixture.worker.runAll()
        fixture.dispatcher.invalidatePending()
        fixture.main.runAll()

        assertTrue(fixture.delivered.isEmpty())
    }

    private class Fixture {
        val worker = CaptureContinuityQueuedExecutor()
        val main = CaptureContinuityQueuedExecutor()
        val delivered = mutableListOf<Map<String, Any?>>()
        val dispatcher = OrderedCaptureEventDispatcher(
            validator = CaptureMessageValidator(maxMessageBytes = 1024, clock = { "now" }),
            worker = worker,
            postToMain = main::execute,
            deliver = delivered::add,
        )

        fun runAll() {
            worker.runAll()
            main.runAll()
        }

        fun assertSingleInterruption() {
            assertEquals(listOf(interruption()), delivered)
        }
    }

    private companion object {
        fun interruption(): Map<String, Any?> = mapOf(
            "version" to 1,
            "kind" to "capture_interrupted",
        )

        fun stringMessage(body: String): String =
            """
            {
              "version": 1,
              "kind": "kcsapi_response",
              "method": "POST",
              "path": "/kcsapi/api_req_sortie/battle",
              "requestParams": {},
              "responseBody": "$body",
              "statusCode": 200,
              "transport": "xhr"
            }
            """.trimIndent()

        fun binaryMessage(body: String): ByteArray {
            val metadata =
                """
                {
                  "version": 1,
                  "kind": "kcsapi_response",
                  "method": "POST",
                  "path": "/kcsapi/api_req_sortie/battle",
                  "requestParams": {},
                  "statusCode": 200,
                  "transport": "fetch"
                }
                """.trimIndent().toByteArray(Charsets.UTF_8)
            val response = body.toByteArray(Charsets.UTF_8)
            return ByteBuffer.allocate(4 + metadata.size + response.size)
                .putInt(metadata.size)
                .put(metadata)
                .put(response)
                .array()
        }
    }
}

private class CaptureContinuityQueuedExecutor : Executor {
    private val tasks = ArrayDeque<Runnable>()

    override fun execute(command: Runnable) {
        tasks.addLast(command)
    }

    fun runAll() {
        while (tasks.isNotEmpty()) tasks.removeFirst().run()
    }
}
