package app.yahagi.kancollebrowser.mods

import com.google.gson.Gson
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/** Connects the user-owned source library to immutable game revisions. Called on the IO mutation queue. */
class GameModLibraryCoordinator @JvmOverloads constructor(
    private val repository: GameModRepository,
    private val library: GameModLibrary,
    private val workspace: File,
    private val progress: GameModProgress? = null,
) {
    private val gson = Gson()
    private val restores = mutableMapOf<String, Boolean>()
    private val pendingSync = File(workspace, "pending-public-sync.json")
    var errorCode: String? = null
        private set
    private var lastScan: Long? = null

    init {
        if (!workspace.isDirectory && !workspace.mkdirs()) throw GameModException("library_write_failed", "Cannot create library working directory")
    }

    fun status(): Map<String, Any?> {
        val value = library.status()
        return value + mapOf("available" to true, "displayName" to value["location"], "uri" to value["identity"],
            "lastScan" to lastScan, "error" to (errorCode ?: if (pendingSync.exists()) "library_backup_pending" else null))
    }

    fun migrateExisting(): Int {
        requirePublicSynchronized()
        val known = (library.status()["packages"] as? List<*>).orEmpty().mapNotNull { (it as? Map<*, *>)?.get("id") as? String }.toSet()
        val applied = repository.status()["applied"] as Map<*, *>
        val appliedIds = (applied["order"] as List<*>).filterIsInstance<String>().toSet()
        var count = 0
        val existing = packages()
        for ((index, pack) in existing.withIndex()) {
            val id = pack["id"] as String
            // Published deletions may still have private metadata after a crash or a
            // deferred cleanup. Only an unapplied deletion can remain active/migratable.
            if (pack["pendingRemoval"] == true && id !in appliedIds) continue
            // The public source may have been edited since the last import. Never overwrite it on reattachment.
            if (id in known) continue
            progress?.startPackage("save", pack["name"] as String, index, existing.size)
            val directory = temporary("migration")
            try {
                repository.exportPackageTree(id, directory)
                val saved = library.savePackage(id, pack["name"] as String, directory)
                repository.attachLibraryFingerprint(id, saved["contentHash"] as String)
                count++
                progress?.update(completedPackages = index + 1)
            } finally { directory.deleteRecursively() }
        }
        if (library.appliedConfiguration() == null && packages().isNotEmpty()) library.saveAppliedConfiguration(repository.exportAppliedConfiguration())
        return count
    }

    fun commitImport(token: String): Map<String, Any?> {
        requirePublicSynchronized()
        val directory = temporary("import")
        try {
            val exported = repository.exportPreflightTree(token, directory)
            val fingerprint = library.fingerprintLocalTree(directory)
            packages().firstOrNull { it["sourceFingerprint"] == fingerprint }?.let { duplicate ->
                repository.discardImport(token)
                progress?.update(completedPackages = 1, totalPackages = 1)
                return duplicate + ("duplicate" to true)
            }
            // Reinstallation can leave a complete public library before the first scan.
            // Reuse its identity, and never overwrite an externally edited source tree.
            val savedPackage = (library.status()["packages"] as? List<*>).orEmpty()
                .filterIsInstance<Map<*, *>>().firstOrNull { it["contentHash"] == fingerprint }
            val existingId = savedPackage?.get("id") as? String
            if (existingId != null) return repository.commitLibraryImport(token, existingId, fingerprint).also {
                progress?.update(completedPackages = 1, totalPackages = 1)
            }
            val id = UUID.randomUUID().toString()
            val saved = library.savePackage(id, exported["name"] as String, directory)
            return repository.commitLibraryImport(token, id, saved["contentHash"] as String).also {
                progress?.update(completedPackages = 1, totalPackages = 1)
            }
        } finally { directory.deleteRecursively() }
    }

    fun scan(): Map<String, Any?> {
        requirePublicSynchronized()
        val preview = library.scan()
        val current = packages().associateBy { it["id"] as String }
        val entries = preview.items.mapIndexed { index, entry ->
            val raw = entry["status"] as? String ?: "invalid"
            val id = entry["id"] as? String
            val installed = current[id]
            val kind = if (raw in setOf("new", "updated", "unchanged")) {
                when {
                    installed == null -> "new"
                    installed["sourceFingerprint"] != entry["contentHash"] -> "updated"
                    else -> "unchanged"
                }
            } else if (raw == "deleted") "missing" else raw
            val reason = entry["reason"] as? String
            val detail = entry["error"] as? String ?: reason?.takeUnless { it.matches(Regex("[a-z][a-z0-9_]*")) }
            entry + mapOf("id" to (id ?: "$kind-$index"), "kind" to kind, "detail" to detail,
                "reason" to reason?.takeIf { it.matches(Regex("[a-z][a-z0-9_]*")) },
                "unsupportedCount" to ((entry["resourceCount"] as? Number)?.toInt()?.minus((entry["supportedCount"] as? Number)?.toInt() ?: 0) ?: 0))
        }
        val status = repository.status()
        val appliedOrder = (status["applied"] as Map<*, *>)["order"] as List<*>
        val restore = (status["sessionId"] as Number).toLong() == 0L && appliedOrder.isEmpty() &&
            library.appliedConfiguration()?.let { (it["order"] as? List<*>)?.isNotEmpty() == true } == true
        restores[preview.token] = restore
        lastScan = System.currentTimeMillis()
        return mapOf("token" to preview.token, "entries" to entries, "restoreAvailable" to restore, "cleanupCount" to preview.cleanupCount)
    }

    fun commitScan(token: String) {
        if (token !in restores) throw GameModException("invalid_token", "The scan preview has expired")
        requirePublicSynchronized()
        try {
            val candidates = library.acceptScan(token)
            val current = packages().associateBy { it["id"] as String }
            val changed = candidates.filter { current[it.id]?.get("sourceFingerprint") != it.contentHash }
            // Validate the whole batch before changing repository metadata, releasing each
            // preview immediately. The repository deliberately limits concurrent previews.
            for ((index, candidate) in changed.withIndex()) {
                progress?.startPackage("validate", candidate.name, index, changed.size)
                val preview = candidate.archive.inputStream().use { repository.preflightLibrary(it, "${candidate.name}.zip") }
                repository.discardImport(preview["token"] as String)
                progress?.update(completedPackages = index + 1)
            }
            for ((index, candidate) in changed.withIndex()) {
                progress?.startPackage("import", candidate.name, index, changed.size)
                val preview = candidate.archive.inputStream().use { repository.preflightLibrary(it, "${candidate.name}.zip") }
                val importToken = preview["token"] as String
                try { repository.commitLibraryImport(importToken, candidate.id, candidate.contentHash) }
                finally { repository.discardImport(importToken) }
                progress?.update(completedPackages = index + 1)
            }
            if (restores[token] == true) library.appliedConfiguration()?.let(repository::restoreLibraryConfiguration)
            errorCode = if (library.completeScan(token).isEmpty()) null else "library_cleanup_failed"
        } finally {
            restores.remove(token)
            library.discardScan(token)
        }
    }

    fun discardScan(token: String) { restores.remove(token); library.discardScan(token) }

    /** Journal before public IO so lost authorization or process death cannot forget unfinished cleanup. */
    fun journalApplied(removedIds: List<String>) {
        val previous = readPending()
        val ids = ((previous?.get("removedIds") as? List<*>)?.filterIsInstance<String>().orEmpty() + removedIds).distinct()
        writePending(mapOf("removedIds" to ids, "configuration" to repository.exportAppliedConfiguration()))
    }

    fun applied(removedIds: List<String>) {
        journalApplied(removedIds)
        retryPending()
    }

    fun retryPending() {
        val pending = readPending() ?: return
        try {
            val config = pending["configuration"] as? Map<*, *> ?: throw GameModException("invalid_config", "Invalid library synchronization journal")
            val ids = (pending["removedIds"] as? List<*>)?.filterIsInstance<String>().orEmpty()
            library.saveAppliedConfiguration(config)
            if (library.deletePackages(ids).isNotEmpty()) { errorCode = "library_cleanup_failed"; return }
            if (!pendingSync.delete() && pendingSync.exists()) throw GameModException("library_write_failed", "Cannot finish library synchronization")
            errorCode = null
        } catch (_: Exception) { errorCode = "library_backup_pending" }
    }

    private fun requirePublicSynchronized() {
        retryPending()
        if (pendingSync.exists()) throw GameModException(errorCode ?: "library_backup_pending",
            "Finish synchronizing the last applied configuration before importing or scanning the library")
    }

    fun dispose() { restores.keys.toList().forEach(::discardScan) }

    @Suppress("UNCHECKED_CAST")
    private fun packages(): List<Map<String, Any?>> = (repository.status()["packages"] as List<*>).filterIsInstance<Map<String, Any?>>()
    private fun temporary(kind: String): File = File(workspace, "$kind-${UUID.randomUUID()}").also {
        if (!it.mkdir()) throw GameModException("library_write_failed", "Cannot create library temporary directory")
    }
    @Suppress("UNCHECKED_CAST")
    private fun readPending(): Map<String, Any?>? = if (!pendingSync.isFile) null else try {
        gson.fromJson(pendingSync.readText(Charsets.UTF_8), Map::class.java) as Map<String, Any?>
    } catch (_: Exception) { throw GameModException("library_metadata_invalid", "The library synchronization journal is damaged") }
    private fun writePending(value: Map<String, Any?>) {
        val temporary = File(workspace, "sync-${UUID.randomUUID()}.tmp")
        try {
            FileOutputStream(temporary).use { stream -> stream.write(gson.toJson(value).toByteArray(Charsets.UTF_8)); stream.fd.sync() }
            atomicMove(temporary, pendingSync)
        } finally { temporary.delete() }
    }

    private fun atomicMove(source: File, destination: File) {
        // Same-filesystem Android rename replaces atomically even on API 24/25.
        // Windows needs NIO replacement; reflect it so older Android never links NIO classes.
        if (source.renameTo(destination)) return
        try {
            val pathType = Class.forName("java.nio.file.Path")
            val optionType = Class.forName("java.nio.file.CopyOption")
            val standardType = Class.forName("java.nio.file.StandardCopyOption")
            val toPath = File::class.java.getMethod("toPath")
            val options = java.lang.reflect.Array.newInstance(optionType, 2)
            java.lang.reflect.Array.set(options, 0, standardType.getField("ATOMIC_MOVE").get(null))
            java.lang.reflect.Array.set(options, 1, standardType.getField("REPLACE_EXISTING").get(null))
            val move = Class.forName("java.nio.file.Files").getMethod("move", pathType, pathType, options.javaClass)
            try { move.invoke(null, toPath.invoke(source), toPath.invoke(destination), options) }
            catch (error: java.lang.reflect.InvocationTargetException) {
                if (error.cause?.javaClass?.name != "java.nio.file.AtomicMoveNotSupportedException") throw error
                val replace = java.lang.reflect.Array.newInstance(optionType, 1)
                java.lang.reflect.Array.set(replace, 0, standardType.getField("REPLACE_EXISTING").get(null))
                move.invoke(null, toPath.invoke(source), toPath.invoke(destination), replace)
            }
        } catch (error: Exception) {
            throw GameModException("library_write_failed", "Cannot atomically persist pending library synchronization")
        }
    }
}
