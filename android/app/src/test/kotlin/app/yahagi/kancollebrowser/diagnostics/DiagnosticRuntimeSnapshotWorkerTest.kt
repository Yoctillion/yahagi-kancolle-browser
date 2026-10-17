package app.yahagi.kancollebrowser.diagnostics

import java.util.ArrayDeque
import java.util.concurrent.Executor
import java.util.concurrent.RejectedExecutionException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class DiagnosticRuntimeSnapshotWorkerTest {
    @Test
    fun `sampling waits for worker and result waits for main dispatch`() {
        val workerQueue = TaskQueue()
        val mainQueue = TaskQueue()
        val sample = mapOf<String, Any>("pssKb" to 42, "lowMemory" to false)
        var sampled = false
        val results = mutableListOf<Result<Map<String, Any>>>()
        val worker = DiagnosticRuntimeSnapshotWorker(workerQueue, mainQueue::execute) {
            sampled = true
            sample
        }

        worker.sample(results::add)
        assertFalse(sampled)
        assertTrue(results.isEmpty())
        workerQueue.runNext()
        assertTrue(sampled)
        assertTrue(results.isEmpty())
        mainQueue.runNext()
        assertSame(sample, results.single().getOrThrow())
    }

    @Test
    fun `sampling failure returns through main queue and next sample still works`() {
        val workerQueue = TaskQueue()
        val mainQueue = TaskQueue()
        val failure = IllegalStateException("memory statistics unavailable")
        var attempts = 0
        val results = mutableListOf<Result<Map<String, Any>>>()
        val worker = DiagnosticRuntimeSnapshotWorker(workerQueue, mainQueue::execute) {
            if (attempts++ == 0) throw failure
            mapOf("pssKb" to 42)
        }

        worker.sample(results::add)
        worker.sample(results::add)
        workerQueue.runAll()
        assertTrue(results.isEmpty())
        mainQueue.runAll()
        assertSame(failure, results[0].exceptionOrNull())
        assertEquals(42, results[1].getOrThrow()["pssKb"])
    }

    @Test
    fun `dispose cancels queued work once without taking an obsolete sample`() {
        val workerQueue = TaskQueue()
        val mainQueue = TaskQueue()
        var samples = 0
        val results = mutableListOf<Result<Map<String, Any>>>()
        val worker = DiagnosticRuntimeSnapshotWorker(workerQueue, mainQueue::execute) {
            samples++
            emptyMap()
        }

        worker.sample(results::add)
        worker.dispose()
        worker.dispose()
        workerQueue.runAll()
        mainQueue.runAll()

        assertEquals(0, samples)
        assertTrue(results.single().exceptionOrNull() is DiagnosticRuntimeSnapshotCancelled)
    }

    @Test
    fun `dispose wins over a sampled result waiting in the main queue`() {
        val workerQueue = TaskQueue()
        val mainQueue = TaskQueue()
        val results = mutableListOf<Result<Map<String, Any>>>()
        val worker = DiagnosticRuntimeSnapshotWorker(workerQueue, mainQueue::execute) {
            mapOf("pssKb" to 42)
        }

        worker.sample(results::add)
        workerQueue.runNext()
        worker.dispose()
        mainQueue.runAll()

        assertTrue(results.single().exceptionOrNull() is DiagnosticRuntimeSnapshotCancelled)
    }

    @Test
    fun `executor rejection completes once without retaining a pending request`() {
        val failure = RejectedExecutionException("executor unavailable")
        val results = mutableListOf<Result<Map<String, Any>>>()
        val worker = DiagnosticRuntimeSnapshotWorker(
            Executor { throw failure },
            { it.run() },
            { error("must not sample") },
        )

        worker.sample(results::add)
        worker.dispose()

        assertSame(failure, results.single().exceptionOrNull())
    }

    @Test
    fun `requests after dispose are cancelled without enqueueing`() {
        val workerQueue = TaskQueue()
        val results = mutableListOf<Result<Map<String, Any>>>()
        val worker = DiagnosticRuntimeSnapshotWorker(workerQueue, { it.run() }) {
            error("must not sample")
        }
        worker.dispose()

        worker.sample(results::add)

        assertTrue(workerQueue.isEmpty)
        assertTrue(results.single().exceptionOrNull() is DiagnosticRuntimeSnapshotCancelled)
    }

    private class TaskQueue : Executor {
        private val tasks = ArrayDeque<Runnable>()
        val isEmpty: Boolean get() = tasks.isEmpty()

        override fun execute(command: Runnable) {
            tasks.addLast(command)
        }

        fun runNext() = tasks.removeFirst().run()

        fun runAll() {
            while (tasks.isNotEmpty()) runNext()
        }
    }
}
