package app.yahagi.kancollebrowser.capture

import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Validates capture messages on one ordered worker and only delivers results
 * that still belong to the currently attached WebView generation.
 */
internal class OrderedCaptureEventDispatcher(
    private val validator: CaptureMessageValidator,
    private val postToMain: (Runnable) -> Unit,
    private val deliver: (Map<String, Any?>) -> Unit,
    worker: Executor? = null,
) {
    private val ownedWorker: ExecutorService? = if (worker == null) {
        Executors.newSingleThreadExecutor { task ->
            Thread(task, "yahagi-capture-validator").apply {
                isDaemon = true
            }
        }
    } else {
        null
    }
    private val worker: Executor = worker ?: requireNotNull(ownedWorker)
    private val generation = AtomicLong(0)
    private val closed = AtomicBoolean(false)

    /** Capture once when installing a listener so late callbacks retain their old generation. */
    val currentGeneration: Long
        get() = generation.get()

    fun submit(
        message: String,
        sourceOrigin: String,
        submittedGeneration: Long = currentGeneration,
    ) {
        enqueue(submittedGeneration) { validator.validate(message, sourceOrigin) }
    }

    fun submit(
        message: ByteArray,
        sourceOrigin: String,
        submittedGeneration: Long = currentGeneration,
    ) {
        // WebMessageCompat owns the incoming buffer. Keep worker lifetime
        // independent from the callback by taking one immutable snapshot.
        val snapshot = message.copyOf()
        enqueue(submittedGeneration) { validator.validate(snapshot, sourceOrigin) }
    }

    fun invalidatePending() {
        generation.incrementAndGet()
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        invalidatePending()
        ownedWorker?.shutdownNow()
    }

    private fun enqueue(submittedGeneration: Long, validate: () -> Map<String, Any?>?) {
        if (!isCurrent(submittedGeneration)) return
        try {
            worker.execute {
                if (!isCurrent(submittedGeneration)) return@execute
                val event = try {
                    validate()
                } catch (_: RuntimeException) {
                    null
                } ?: mapOf(
                    "version" to 1,
                    "kind" to "capture_interrupted",
                )
                if (!isCurrent(submittedGeneration)) return@execute
                postToMain(
                    Runnable {
                        if (isCurrent(submittedGeneration)) deliver(event)
                    },
                )
            }
        } catch (_: RejectedExecutionException) {
            // A capture racing with Activity disposal is intentionally dropped.
        }
    }

    private fun isCurrent(submittedGeneration: Long): Boolean =
        !closed.get() && generation.get() == submittedGeneration
}
