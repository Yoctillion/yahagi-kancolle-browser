package app.yahagi.kancollebrowser.diagnostics

import java.util.concurrent.Executor
import java.util.concurrent.RejectedExecutionException

/** Owns sampling requests; sample, dispose and completion dispatch run on the main thread. */
internal class DiagnosticRuntimeSnapshotWorker(
    private val worker: Executor,
    private val postToMain: (Runnable) -> Unit,
    private val snapshot: () -> Map<String, Any>,
) {
    @Volatile
    private var disposed = false
    private val pending = mutableSetOf<Request>()

    fun sample(complete: (Result<Map<String, Any>>) -> Unit) {
        if (disposed) {
            complete(Result.failure(DiagnosticRuntimeSnapshotCancelled()))
            return
        }
        val request = Request(complete)
        pending.add(request)
        try {
            worker.execute {
                if (disposed) return@execute
                val result = runCatching(snapshot)
                postToMain(Runnable { finish(request, result) })
            }
        } catch (error: RejectedExecutionException) {
            finish(request, Result.failure(error))
        }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        val cancelled = pending.toList()
        pending.clear()
        cancelled.forEach { it.complete(Result.failure(DiagnosticRuntimeSnapshotCancelled())) }
    }

    private fun finish(request: Request, result: Result<Map<String, Any>>) {
        if (pending.remove(request)) request.complete(result)
    }

    private class Request(val complete: (Result<Map<String, Any>>) -> Unit)
}

internal class DiagnosticRuntimeSnapshotCancelled : IllegalStateException(
    "The diagnostic memory sample was cancelled.",
)
