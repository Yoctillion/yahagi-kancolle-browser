package app.yahagi.kancollebrowser.fonts

import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicBoolean

/** Physical pixel limits are checked before any font decoding or bitmap allocation. */
internal data class CustomFontPreviewRequest(
    val id: String, val text: String, val width: Int, val fontSize: Float,
    val locale: String, val color: Int,
) {
    companion object {
        const val MAX_HEIGHT = 512
        const val MAX_PIXELS = 524288
        const val MAX_PNG_BYTES = 3 * 1024 * 1024
        private val validId = Regex("[0-9a-f]{64}")
        private val locales = setOf("zh", "zh-Hant", "ja", "ko", "en")

        fun fromArguments(arguments: Any?): CustomFontPreviewRequest {
            val values = arguments as? Map<*, *> ?: invalid()
            val id = values["id"] as? String ?: invalid()
            val text = values["text"] as? String ?: invalid()
            val width = values["width"] as? Int ?: invalid()
            val fontSize = values["fontSize"] as? Double ?: invalid()
            val locale = values["locale"] as? String ?: invalid()
            val color = when (val value = values["color"]) {
                is Int -> value.toLong()
                is Long -> value
                else -> invalid()
            }
            if (!validId.matches(id) || text.isEmpty() || text.length > 512 ||
                width !in 160..1024 || !fontSize.isFinite() || fontSize !in 12.0..72.0 ||
                locale !in locales || color !in Int.MIN_VALUE.toLong()..0xffffffffL) invalid()
            return CustomFontPreviewRequest(id, text, width, fontSize.toFloat(), locale, color.toInt())
        }

        private fun invalid(): Nothing =
            throw CustomFontException("invalid_preview", "Invalid font preview parameters")
    }

    fun bitmapHeight(layoutHeight: Int): Int {
        if (layoutHeight <= 0) throw CustomFontException("invalid_preview", "Invalid font preview dimensions")
        return minOf(layoutHeight, MAX_HEIGHT, MAX_PIXELS / width)
    }
}

internal class CustomFontPreviewOutput(private val maxBytes: Int) : OutputStream() {
    private val output = ByteArrayOutputStream(minOf(maxBytes, 16 * 1024))

    override fun write(value: Int) {
        checkCapacity(1)
        output.write(value)
    }

    override fun write(bytes: ByteArray, offset: Int, length: Int) {
        if (offset < 0 || length < 0 || offset > bytes.size - length) throw IndexOutOfBoundsException()
        checkCapacity(length)
        output.write(bytes, offset, length)
    }

    private fun checkCapacity(length: Int) {
        if (length > maxBytes - output.size()) {
            throw CustomFontException("invalid_preview", "The font preview image exceeds its size limit")
        }
    }

    fun toByteArray(): ByteArray = output.toByteArray()
}

/** Reject additional previews instead of growing the single worker's queue. */
internal class CustomFontPreviewGate {
    private val active = AtomicBoolean(false)
    fun tryAcquire(): Boolean = active.compareAndSet(false, true)
    fun release() { active.set(false) }
}
