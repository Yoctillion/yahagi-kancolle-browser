package app.yahagi.kancollebrowser.backup

import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.Properties
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** Durable state for an export that outlives its Flutter/Activity caller. */
class PendingBackupExportStore(
    private val root: File,
    private val removeCompletedTransaction: (File) -> Boolean = { it.deleteRecursively() },
) {
    companion object {
        const val FIRST_PICKER_REQUEST = 2412
        const val LAST_PICKER_REQUEST = 65535
        private val locks = ConcurrentHashMap<String, Any>()
        private val tokenPattern = Regex("[0-9a-f-]{36}")
    }
    private val rootLock = locks.getOrPut(root.canonicalPath) { Any() }
    interface Documents {
        fun write(uri: String, source: File)
        fun matches(uri: String, source: File): Boolean
        fun delete(uri: String): Boolean
    }
    data class Entry(
        val token: String,
        val name: String,
        val uri: String? = null,
        val grantFlags: Int = 0,
        val verified: Boolean = false,
        val discardRequested: Boolean = false,
        val createdAt: Long = 0,
        val size: Long = 0,
        val sha256: String = "",
        val requestCode: Int = FIRST_PICKER_REQUEST,
    )

    fun stage(name: String, bytes: ByteArray): Entry = synchronized(rootLock) {
        require(name.endsWith(".yhb") && name.length < 180 &&
            !name.contains('/') && !name.contains('\\')) { "Invalid backup name" }
        require(bytes.isNotEmpty() && bytes.size <= 100 * 1024 * 1024) { "Invalid backup size" }
        check(root.isDirectory || root.mkdirs()) { "Unable to stage backup" }
        // A new explicit export supersedes an abandoned picker, never a selected
        // destination. No provider I/O runs while holding this staging lock.
        entries().filter { it.uri == null }.forEach { cancelPicker(it.token) }
        val entry = Entry(
            token = UUID.randomUUID().toString(), name = name,
            createdAt = System.currentTimeMillis(), size = bytes.size.toLong(),
            sha256 = digest(bytes),
            requestCode = allocateRequestCode(),
        )
        val directory = transactionDirectory(entry.token)
        check(directory.mkdir()) { "Unable to stage backup" }
        try {
            FileOutputStream(sourceFile(entry.token)).use { output ->
                output.write(bytes)
                output.fd.sync()
            }
            persist(entry)
            entry
        } catch (error: Throwable) {
            directory.deleteRecursively()
            throw error
        }
    }

    fun awaitingPicker(): Entry? = synchronized(rootLock) {
        entries().filter { it.uri == null && !it.discardRequested }.maxByOrNull { it.createdAt }
    }

    fun forPicker(requestCode: Int): Entry? = synchronized(rootLock) {
        entries().firstOrNull { it.requestCode == requestCode }
    }

    fun sourceFile(token: String): File = File(transactionDirectory(token), "payload.yhb")

    fun get(token: String): Entry? = synchronized(metadataLock(token)) { readEntry(token) }

    fun select(token: String, uri: String, grantFlags: Int) = synchronized(metadataLock(token)) {
        val entry = get(token) ?: error("Export is no longer available")
        require(!entry.discardRequested) { "Export was discarded" }
        require(entry.uri == null || entry.uri == uri) { "Export already has a destination" }
        persist(entry.copy(uri = uri, grantFlags = entry.grantFlags or grantFlags))
    }

    fun writeAndVerify(token: String, documents: Documents) = synchronized(tokenLock(token)) {
        val entry = get(token) ?: error("Export is no longer available")
        if (entry.verified) return@synchronized
        require(!entry.discardRequested) { "Export was discarded" }
        val uri = entry.uri ?: error("Export destination is missing")
        val source = sourceFile(token)
        require(source.isFile && source.length() == entry.size && digest(source) == entry.sha256) {
            "Staged backup is incomplete"
        }
        // The process can die after the provider commits complete bytes but
        // before our verified marker. Never truncate that completed document.
        if (!documents.matches(uri, source)) {
            documents.write(uri, source)
            require(documents.matches(uri, source)) { "Saved backup verification failed" }
        }
        // This durable marker precedes releasing the payload or notifying Dart.
        // A missing Dart completion must never delete a successfully saved file.
        synchronized(metadataLock(token)) {
            persist((readEntry(token) ?: error("Export vanished")).copy(verified = true))
        }
        source.delete()
    }

    fun recover(documents: Documents, onSettled: (Entry) -> Unit = {}) {
        val pending = synchronized(rootLock) { entries() }
        for (entry in pending) {
            if (entry.uri == null) continue // The picker may still deliver its result.
            try {
                if (entry.discardRequested) discard(entry.token, documents)
                else writeAndVerify(entry.token, documents)
            } catch (_: Exception) {
                // A readback or metadata failure can follow a complete write.
                // Only a proven mismatch authorizes automatic deletion.
                runCatching { discardIncomplete(entry.token, documents) }
            }
            val current = get(entry.token)
            if (current == null || current.verified) onSettled(current ?: entry)
        }
    }

    /** Explicit discard is separate: an uncertain provider read must retain recovery data. */
    fun discardIncomplete(token: String, documents: Documents): Boolean = synchronized(tokenLock(token)) {
        val entry = get(token) ?: return@synchronized true
        if (entry.verified) return@synchronized false
        if (entry.discardRequested || entry.uri == null) return@synchronized discard(token, documents)
        val source = sourceFile(token)
        // Without the original complete source we cannot prove a target partial.
        if (!source.isFile || source.length() != entry.size || digest(source) != entry.sha256) {
            return@synchronized false
        }
        if (documents.matches(entry.uri, source)) {
            persist(entry.copy(verified = true))
            source.delete()
            false
        } else {
            discard(token, documents)
        }
    }

    fun complete(token: String) = synchronized(tokenLock(token)) {
        val entry = get(token) ?: return@synchronized
        require(entry.verified && !entry.discardRequested) { "Saved backup has not been verified" }
        // A failed app-private cleanup must not turn a successful user export
        // into a Dart failure followed by deletion of the verified document.
        runCatching { removeCompletedTransaction(transactionDirectory(token)) }
        Unit
    }

    fun discard(token: String, documents: Documents): Boolean = synchronized(tokenLock(token)) {
        val entry = get(token) ?: return@synchronized true
        persist(entry.copy(discardRequested = true))
        sourceFile(token).delete()
        val removed = entry.uri == null || runCatching { documents.delete(entry.uri) }.getOrDefault(false)
        if (removed) {
            check(transactionDirectory(token).deleteRecursively()) { "Unable to remove export transaction" }
        }
        removed
    }

    fun cancelPicker(token: String) = synchronized(metadataLock(token)) {
        if (readEntry(token)?.uri == null) {
            check(transactionDirectory(token).deleteRecursively()) { "Unable to remove staged export" }
        }
    }

    private fun transactionDirectory(token: String): File {
        require(tokenPattern.matches(token)) { "Invalid export token" }
        return File(root, token)
    }

    private fun tokenLock(token: String): Any =
        locks.getOrPut(transactionDirectory(token).canonicalPath) { Any() }

    private fun metadataLock(token: String): Any =
        locks.getOrPut("${transactionDirectory(token).canonicalPath}:metadata") { Any() }

    private fun entries(): List<Entry> = root.listFiles().orEmpty()
        .filter { it.isDirectory && tokenPattern.matches(it.name) }
        .mapNotNull { directory ->
            get(directory.name).also { entry ->
                // stage() and enumeration share rootLock, so this cannot race
                // an in-progress stage that has not yet published metadata.
                if (entry == null) directory.deleteRecursively()
            }
        }

    private fun allocateRequestCode(): Int {
        val current = File(root, "picker-request-code")
        val pending = File(root, "picker-request-code.pending")
        val previous = listOf(pending, current).firstNotNullOfOrNull { file ->
            runCatching { file.readText().trim().toInt() }
                .getOrNull()?.takeIf { it in FIRST_PICKER_REQUEST..LAST_PICKER_REQUEST }
        } ?: (entries().maxOfOrNull { it.requestCode } ?: (FIRST_PICKER_REQUEST - 1))
        val next = if (previous == LAST_PICKER_REQUEST) FIRST_PICKER_REQUEST else previous + 1
        require(entries().none { it.requestCode == next }) { "Export picker request is still in use" }
        FileOutputStream(pending).use { output ->
            output.write(next.toString().toByteArray(Charsets.UTF_8))
            output.fd.sync()
        }
        check(!current.exists() || current.delete()) { "Unable to rotate picker request" }
        check(pending.renameTo(current)) { "Unable to commit picker request" }
        return next
    }

    private fun readEntry(token: String): Entry? {
        val directory = transactionDirectory(token)
        // A fully synced replacement is usable even if the process died before
        // rename. The prior metadata remains available during every replacement.
        for (name in listOf("transaction.pending", "transaction.properties", "transaction.previous")) {
            val file = File(directory, name)
            if (!file.isFile) continue
            val entry = runCatching {
                val properties = Properties().apply { file.inputStream().use { load(it) } }
                require(properties.getProperty("token") == token)
                val hash = properties.getProperty("sha256")
                require(hash?.matches(Regex("[0-9a-f]{64}")) == true)
                Entry(
                    token = token, name = properties.getProperty("name") ?: error("Missing name"),
                    uri = properties.getProperty("uri"),
                    grantFlags = properties.getProperty("grantFlags").toInt(),
                    verified = properties.getProperty("verified").toBooleanStrict(),
                    discardRequested = properties.getProperty("discardRequested").toBooleanStrict(),
                    createdAt = properties.getProperty("createdAt").toLong(),
                    size = properties.getProperty("size").toLong(), sha256 = hash,
                    requestCode = properties.getProperty("requestCode")?.toInt() ?: FIRST_PICKER_REQUEST,
                )
            }.getOrNull()
            if (entry != null) return entry
        }
        return null
    }

    private fun persist(entry: Entry) = synchronized(metadataLock(entry.token)) {
        val directory = transactionDirectory(entry.token)
        val current = File(directory, "transaction.properties")
        val pending = File(directory, "transaction.pending")
        val previous = File(directory, "transaction.previous")
        val properties = Properties().apply {
            setProperty("token", entry.token)
            setProperty("name", entry.name)
            entry.uri?.let { setProperty("uri", it) }
            setProperty("grantFlags", entry.grantFlags.toString())
            setProperty("verified", entry.verified.toString())
            setProperty("discardRequested", entry.discardRequested.toString())
            setProperty("createdAt", entry.createdAt.toString())
            setProperty("size", entry.size.toString())
            setProperty("sha256", entry.sha256)
            setProperty("requestCode", entry.requestCode.toString())
        }
        FileOutputStream(pending).use { output ->
            properties.store(output, null)
            output.fd.sync()
        }
        check(!previous.exists() || previous.delete()) { "Unable to replace export metadata" }
        check(!current.exists() || current.renameTo(previous)) { "Unable to preserve export metadata" }
        check(pending.renameTo(current)) { "Unable to commit export metadata" }
        previous.delete()
    }

    private fun digest(bytes: ByteArray): String = hex(MessageDigest.getInstance("SHA-256").digest(bytes))
    private fun digest(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return hex(digest.digest())
    }
    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
}
