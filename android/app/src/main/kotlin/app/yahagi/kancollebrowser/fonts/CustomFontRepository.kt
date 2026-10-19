package app.yahagi.kancollebrowser.fonts

import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.RandomAccessFile
import java.security.MessageDigest

internal class CustomFontException(val code: String, message: String) : Exception(message)
internal data class ImportedCustomFont(val id: String, val name: String, val path: String) {
    fun toMap(): Map<String, String> = mapOf("id" to id, "name" to name, "path" to path)
}

/** Owns only immutable, content-addressed single-font files in the app's private directory. */
internal class CustomFontRepository(
    private val root: File,
    private val validateLoad: (File) -> Unit = {},
) {
    companion object {
        const val MAX_BYTES = 32L * 1024 * 1024
        private val validId = Regex("[0-9a-f]{64}")
        private val ownedFont = Regex("([0-9a-f]{64})\\.(?:ttf|otf)")
        private val stagedImport = Regex("\\.import-.+\\.tmp")
        // NIO is available on Android 26+ and the host JVM. Optional reflection keeps
        // API 24/25 compatible; Android's canonicalFile resolves links on those APIs.
        // Windows canonicalFile alone does not resolve a symbolic link.
        private val symbolicLinkDetector: ((File) -> Boolean)? = try {
            val pathClass = Class.forName("java.nio.file.Path")
            val toPath = File::class.java.getMethod("toPath")
            val isLink = Class.forName("java.nio.file.Files").getMethod("isSymbolicLink", pathClass)
            val detector: (File) -> Boolean = { isLink.invoke(null, toPath.invoke(it)) as Boolean }
            detector
        } catch (_: ReflectiveOperationException) { null }

        private fun isSymbolicLink(file: File): Boolean =
            symbolicLinkDetector?.invoke(file) ?: (file.canonicalFile != file.absoluteFile)
    }

    @Synchronized fun importFont(
        input: InputStream,
        name: String,
        isCancelled: () -> Boolean = { false },
    ): ImportedCustomFont {
        var temporary: File? = null
        try {
            val (directory, staged, id) = input.use { source ->
                val directory = privateRoot()
                val staged = File.createTempFile(".import-", ".tmp", directory).also { temporary = it }
                val digest = MessageDigest.getInstance("SHA-256")
                FileOutputStream(staged).use { output ->
                    val buffer = ByteArray(8192)
                    var total = 0L
                    while (true) {
                        checkActive(isCancelled)
                        val count = source.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        total += count
                        if (total > MAX_BYTES) throw CustomFontException("font_too_large", "Fonts must be 32 MiB or smaller")
                        output.write(buffer, 0, count)
                        digest.update(buffer, 0, count)
                    }
                    output.fd.sync()
                }
                Triple(directory, staged, digest.digest().joinToString("") { "%02x".format(it) })
            } // A provider close failure must happen before publishing the private file.
            val extension = validateSfnt(staged)
            checkActive(isCancelled)
            try { validateLoad(staged) } catch (error: Exception) {
                throw CustomFontException("invalid_font", "The selected font cannot be loaded")
            }
            val destination = privateFile(directory, "$id.$extension")
            checkActive(isCancelled)
            if (destination.exists()) {
                if (!destination.isFile || destination.length() != staged.length() || hash(destination) != id) {
                    throw CustomFontException("font_import_failed", "An existing font file is damaged")
                }
            } else if (!staged.renameTo(destination)) {
                throw CustomFontException("font_import_failed", "Unable to install the selected font")
            }
            val displayName = name.filterNot(Char::isISOControl).trim().take(240).ifEmpty { "Custom font.$extension" }
            return ImportedCustomFont(id, displayName, destination.absolutePath)
        } catch (error: CustomFontException) {
            throw error
        } catch (error: Exception) {
            throw CustomFontException("font_import_failed", "Unable to read or store the selected font")
        } finally {
            temporary?.delete()
        }
    }

    /** Keeps preview reads and rendering atomic with removal/startup cleanup. */
    @Synchronized fun <T> withFontFile(id: String, operation: (File) -> T): T {
        if (!validId.matches(id)) throw CustomFontException("invalid_font_id", "Invalid custom font identifier")
        val directory = privateRoot()
        for (extension in listOf("ttf", "otf")) {
            val file = privateFile(directory, "$id.$extension")
            if (!file.exists()) continue
            if (!file.isFile || file.length() !in 12L..MAX_BYTES) break
            return operation(file)
        }
        throw CustomFontException("font_unreadable", "The custom font is unavailable")
    }

    @Synchronized fun removeFont(id: String) {
        if (!validId.matches(id)) throw CustomFontException("invalid_font_id", "Invalid custom font identifier")
        val directory = privateRoot()
        for (extension in listOf("ttf", "otf")) {
            val file = privateFile(directory, "$id.$extension")
            if (file.exists() && (!file.isFile || !file.delete())) {
                throw CustomFontException("font_remove_failed", "Unable to remove the custom font")
            }
        }
    }

    /** Reclaims files whose Dart owner disappeared before a selection was persisted. */
    @Synchronized fun pruneUnused(keepIds: Set<String>) {
        if (keepIds.any { !validId.matches(it) }) {
            throw CustomFontException("invalid_font_id", "Invalid custom font identifier")
        }
        val directory = privateRoot()
        val files = directory.listFiles()
            ?: throw CustomFontException("font_remove_failed", "Unable to inspect custom font storage")
        for (file in files) {
            val font = ownedFont.matchEntire(file.name)
            if (font == null && !stagedImport.matches(file.name)) continue
            if (font != null && font.groupValues[1] in keepIds) continue
            // Never traverse directories or follow a link outside the anchored private root.
            if (file.canonicalFile != file || file.parentFile != directory || !file.isFile) continue
            if (!file.delete()) {
                throw CustomFontException("font_remove_failed", "Unable to remove an unused custom font")
            }
        }
    }

    private fun privateRoot(): File {
        val parent = root.absoluteFile.parentFile
            ?: throw CustomFontException("font_import_failed", "Private font storage is unavailable")
        val anchored = File(parent.canonicalFile, root.name)
        if (isSymbolicLink(anchored) || anchored.canonicalFile != anchored || (!anchored.isDirectory && !anchored.mkdirs())) {
            throw CustomFontException("font_import_failed", "Private font storage is unavailable")
        }
        return anchored
    }

    private fun privateFile(directory: File, name: String): File = File(directory, name).also {
        if (isSymbolicLink(it) || it.canonicalFile != it || it.parentFile != directory) {
            throw CustomFontException("font_import_failed", "Invalid private font path")
        }
    }

    private fun checkActive(isCancelled: () -> Boolean) {
        if (isCancelled()) throw CustomFontException("activity_destroyed", "The font import was cancelled")
    }

    private fun hash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    /** sfnt uses unsigned offsets; validate in Long before any seeks or additions. */
    private fun validateSfnt(file: File): String = RandomAccessFile(file, "r").use { font ->
        fun invalid(): Nothing = throw CustomFontException("invalid_font", "Select a valid single-font TTF or OTF file")
        val size = font.length()
        if (size < 12) invalid()
        val extension = when (font.readInt()) {
            0x00010000, 0x74727565 -> "ttf"
            0x4f54544f -> "otf"
            else -> invalid() // TTC, WOFF and WOFF2 are intentionally unsupported.
        }
        val count = font.readUnsignedShort()
        val directoryEnd = 12L + count * 16L
        if (count == 0 || directoryEnd > size) invalid()
        font.seek(12)
        val tags = mutableSetOf<Int>()
        val ranges = mutableListOf<Pair<Long, Long>>()
        repeat(count) {
            val tag = font.readInt()
            if (!tags.add(tag) || (0..3).any { ((tag ushr (it * 8)) and 0xff) !in 0x20..0x7e }) invalid()
            font.readInt() // Checksums are left to the platform font decoder.
            val offset = font.readInt().toLong() and 0xffffffffL
            val length = font.readInt().toLong() and 0xffffffffL
            if (offset < directoryEnd || offset % 4 != 0L || offset > size || length > size - offset) invalid()
            if (length > 0) ranges.add(offset to offset + length)
        }
        if (ranges.isEmpty()) invalid()
        val sorted = ranges.sortedBy { it.first }
        for (index in 1 until sorted.size) if (sorted[index].first < sorted[index - 1].second) invalid()
        extension
    }
}
