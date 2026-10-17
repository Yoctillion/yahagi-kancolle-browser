package app.yahagi.kancollebrowser.capture

import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

internal data class ScreenshotExport(val value: Any, val discard: () -> Unit = {})

internal class ScreenshotScanCleanup<T>(
    private val delete: (T) -> Unit,
) {
    private val discarded = AtomicBoolean(false)
    private val scanned = AtomicReference<T?>()

    fun discard() {
        discarded.set(true)
        scanned.get()?.let(delete)
    }

    fun onScanned(uri: T?) {
        scanned.set(uri)
        // A delivered export remains valid after its Activity closes.
        if (discarded.get()) uri?.let(delete)
    }
}

internal fun writeScreenshotExport(
    value: Any,
    discard: () -> Unit,
    write: () -> Unit,
): ScreenshotExport {
    try {
        write()
        return ScreenshotExport(value, discard)
    } catch (error: Exception) {
        runCatching(discard).exceptionOrNull()?.let { cleanupError ->
            if (cleanupError !== error) error.addSuppressed(cleanupError)
        }
        throw error
    }
}

/** Call submit/close on the UI thread. Accepted inputs are exclusively owned by the worker. */
internal class ScreenshotExportWorker(
    private val dispatchMain: (Runnable) -> Boolean,
    private val reportFailure: (Throwable) -> Unit = {},
) {
    private val executor = ThreadPoolExecutor(
        1, 1, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue(1),
        { runnable -> Thread(runnable, "game-screenshot-export").apply { isDaemon = true } },
        ThreadPoolExecutor.AbortPolicy(),
    )
    private val jobs = mutableSetOf<Job>()
    private var closed = false

    fun submit(
        work: (() -> Boolean) -> ScreenshotExport,
        release: () -> Unit,
        onComplete: (Result<ScreenshotExport>) -> Boolean,
    ) {
        val job = Job()
        try {
            synchronized(jobs) {
                if (closed) throw RejectedExecutionException("Screenshot worker is closed")
                jobs.add(job)
                executor.execute {
                    try {
                        val result = try {
                            if (job.cancelled.get()) return@execute
                            Result.success(work(job.cancelled::get))
                        } catch (error: Exception) {
                            Result.failure(error)
                        } finally {
                            release()
                        }
                        var accepted = false
                        try {
                            if (job.cancelled.get()) return@execute
                            val posted = runCatching { dispatchMain(Runnable {
                                try {
                                    if (!job.cancelled.get() && job.claimed.compareAndSet(false, true)) {
                                        accepted = onComplete(result)
                                    }
                                } finally {
                                    job.delivered.countDown()
                                }
                            }) }.getOrElse { error ->
                                reportFailure(error)
                                false
                            }
                            // Waiting here keeps all file/provider cleanup on the worker. close()
                            // releases the wait even when the main looper discards this callback.
                            if (posted) job.delivered.await()
                        } finally {
                            if (!accepted) result.getOrNull()?.let {
                                runCatching(it.discard).onFailure(reportFailure)
                            }
                        }
                    } finally {
                        synchronized(jobs) { jobs.remove(job) }
                    }
                }
            }
        } catch (error: RejectedExecutionException) {
            synchronized(jobs) { jobs.remove(job) }
            release()
            onComplete(Result.failure(error))
        }
    }

    fun close() {
        synchronized(jobs) {
            closed = true
            jobs.forEach {
                it.cancelled.set(true)
                it.delivered.countDown()
            }
            // Queued jobs still execute their finally/release; never recycle a running bitmap here.
            executor.shutdown()
        }
    }

    private class Job {
        val cancelled = AtomicBoolean(false)
        val claimed = AtomicBoolean(false)
        val delivered = CountDownLatch(1)
    }
}
