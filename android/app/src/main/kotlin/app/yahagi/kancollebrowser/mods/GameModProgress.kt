package app.yahagi.kancollebrowser.mods

import java.util.UUID

/** Small progress-only monitor. Never acquire a repository, document or mutation lock here. */
class GameModProgress(private val monotonicMillis: () -> Long = { System.nanoTime() / 1_000_000L }) {
    private class State(val id: String, val operation: String, val started: Long) {
        var active = true
        var phase = "discover"
        var completedPackages = 0
        var totalPackages: Int? = null
        var currentPackage: String? = null
        var currentFile: String? = null
        var completedFiles = 0
        var totalFiles: Int? = null
        var completedBytes = 0L
        var totalBytes: Long? = null
        var finished: Long? = null
    }
    private var state: State? = null
    private val producer = ThreadLocal<String>()

    @Synchronized fun begin(operation: String): String {
        val value = State(UUID.randomUUID().toString(), operation, monotonicMillis())
        state = value
        producer.set(value.id)
        return value.id
    }

    /** Bind synchronous IO to its token without holding the progress monitor during file work. */
    fun <T> withOperation(id: String, block: () -> T): T {
        val previous = producer.get()
        producer.set(id)
        try { return block() }
        finally { if (previous == null) producer.remove() else producer.set(previous) }
    }

    private fun activeState(): State? = state?.takeIf { it.active && it.id == producer.get() }

    @Synchronized fun update(
        phase: String? = null,
        completedPackages: Int? = null,
        totalPackages: Int? = null,
        currentPackage: String? = null,
        currentFile: String? = null,
        completedFiles: Int? = null,
        totalFiles: Int? = null,
        completedBytes: Long? = null,
        totalBytes: Long? = null,
    ) {
        val value = activeState() ?: return
        phase?.let { value.phase = it }
        completedPackages?.let { value.completedPackages = it.coerceAtLeast(0) }
        totalPackages?.let { value.totalPackages = it.coerceAtLeast(0) }
        currentPackage?.let { value.currentPackage = it.take(240) }
        currentFile?.let { value.currentFile = it.take(240) }
        completedFiles?.let { value.completedFiles = it.coerceAtLeast(0) }
        totalFiles?.let { value.totalFiles = it.coerceAtLeast(0) }
        completedBytes?.let { value.completedBytes = it.coerceAtLeast(0L) }
        totalBytes?.let { value.totalBytes = it.coerceAtLeast(0L) }
    }

    @Synchronized fun startPackage(phase: String, name: String, completedPackages: Int, totalPackages: Int?) {
        val value = activeState() ?: return
        value.phase = phase
        value.currentPackage = name.take(240)
        value.completedPackages = completedPackages.coerceAtLeast(0)
        value.totalPackages = totalPackages?.coerceAtLeast(0)
        value.currentFile = null
        value.completedFiles = 0
        value.totalFiles = null
        value.completedBytes = 0L
        value.totalBytes = null
    }

    /** Replaces inner progress, including unknown totals, when a new pass starts. */
    @Synchronized fun files(completedFiles: Int, totalFiles: Int?, currentFile: String?, completedBytes: Long, totalBytes: Long?) {
        val value = activeState() ?: return
        value.completedFiles = completedFiles.coerceAtLeast(0)
        value.totalFiles = totalFiles?.coerceAtLeast(0)
        value.currentFile = currentFile?.take(240)
        value.completedBytes = completedBytes.coerceAtLeast(0L)
        value.totalBytes = totalBytes?.coerceAtLeast(0L)
    }

    @Synchronized fun finish(id: String) {
        val value = state?.takeIf { it.id == id && it.active } ?: return
        value.active = false
        value.phase = "complete"
        value.finished = monotonicMillis()
    }

    @Synchronized fun snapshot(): Map<String, Any?>? {
        val value = state ?: return null
        return linkedMapOf(
            "operationId" to value.id, "operation" to value.operation,
            "phase" to value.phase, "active" to value.active,
            "completedPackages" to value.completedPackages, "totalPackages" to value.totalPackages,
            "currentPackage" to value.currentPackage, "currentFile" to value.currentFile,
            "completedFiles" to value.completedFiles, "totalFiles" to value.totalFiles,
            "completedBytes" to value.completedBytes, "totalBytes" to value.totalBytes,
            "elapsedMillis" to ((value.finished ?: monotonicMillis()) - value.started).coerceAtLeast(0L),
        )
    }
}
