package app.yahagi.kancollebrowser.browser

import java.io.File
import java.security.MessageDigest
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID

/**
 * Simple on-disk cache for bypassed gadget files.
 *
 * Entries expire after [maxAgeMs] and the whole cache is trimmed to [maxBytes].
 * Failures are swallowed on purpose: a broken cache must never break the bypass path.
 */
class GadgetBypassCache(
    private val cacheDir: File,
    private val maxBytes: Long = 200L * 1024 * 1024,
    private val maxAgeMs: Long = 24L * 60 * 60 * 1000,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private var generation = 0L
    init {
        cacheDir.mkdirs()
    }

    @Synchronized
    fun generation(): Long = generation

    @Synchronized
    fun get(url: String): ByteArray? {
        val file = fileFor(url)
        if (!file.isFile) return null
        if (now() - file.lastModified() > maxAgeMs) {
            file.delete()
            return null
        }
        if (file.length() > maxBytes) { file.delete(); return null }
        return runCatching { file.readBytes() }.getOrElse { file.delete(); null }
    }

    @Synchronized
    fun put(url: String, bytes: ByteArray, expectedGeneration: Long? = null) {
        if (expectedGeneration != null && expectedGeneration != generation || bytes.size > maxBytes) return
        var temporary: File? = null
        try {
            val file = fileFor(url)
            file.parentFile?.mkdirs()
            temporary = File(cacheDir, "${UUID.randomUUID()}.part")
            temporary.writeBytes(bytes)
            Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING)
            file.setLastModified(now())
            evictIfNeeded()
        } catch (e: Exception) {
            // Never let cache write failures propagate.
        } finally { temporary?.delete() }
    }

    @Synchronized
    fun remove(url: String) { fileFor(url).delete() }

    @Synchronized
    fun clear() {
        generation++
        cacheDir.listFiles()?.forEach { it.delete() }
    }

    @Synchronized
    fun sizeBytes(): Long = cacheDir.listFiles()?.sumOf { it.length() } ?: 0L

    private fun evictIfNeeded() {
        while (sizeBytes() > maxBytes) {
            val oldest = cacheDir.listFiles()
                ?.filter { it.isFile }
                ?.minByOrNull { it.lastModified() }
                ?: return
            if (!oldest.delete()) return
        }
    }

    private fun fileFor(url: String): File {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(url.toByteArray())
            .joinToString("") { "%02x".format(it) }
        return File(cacheDir, "$digest.cache")
    }
}
