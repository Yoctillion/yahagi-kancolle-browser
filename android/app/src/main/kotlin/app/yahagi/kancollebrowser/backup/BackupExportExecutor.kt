package app.yahagi.kancollebrowser.backup

import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean

/** Keeps export work alive independently of the initiating Activity. */
internal class BackupExportExecutor(
    private val timeoutMillis: Long = 60_000,
    private val maxConcurrent: Int = 4,
) : AutoCloseable {
    private val worker = ThreadPoolExecutor(
        0, maxConcurrent, 30, TimeUnit.SECONDS, SynchronousQueue(),
        { task -> Thread(task, "backup-export-io").apply { isDaemon = true } },
        ThreadPoolExecutor.AbortPolicy(),
    )
    private val watchdog = ScheduledThreadPoolExecutor(1) { task ->
        Thread(task, "backup-export-deadline").apply { isDaemon = true }
    }.apply { removeOnCancelPolicy = true }

    fun execute(
        timeoutMillis: Long = this.timeoutMillis,
        onFailure: (Throwable) -> Unit = {},
        work: () -> Unit,
    ) {
        val replied = AtomicBoolean(false)
        val deadline = watchdog.schedule({
            if (replied.compareAndSet(false, true)) onFailure(TimeoutException(
                "Backup document I/O timed out; staged data is retained for recovery",
            ))
        }, timeoutMillis, TimeUnit.MILLISECONDS)
        try {
            worker.execute {
                try {
                    work()
                } catch (error: Throwable) {
                    if (replied.compareAndSet(false, true)) onFailure(error)
                } finally {
                    replied.set(true)
                    deadline.cancel(false)
                }
            }
        } catch (error: RejectedExecutionException) {
            deadline.cancel(false)
            if (replied.compareAndSet(false, true)) onFailure(IllegalStateException(
                "Backup document provider is still busy; retry later", error,
            ))
        }
    }

    override fun close() { worker.shutdownNow(); watchdog.shutdownNow() }
}
