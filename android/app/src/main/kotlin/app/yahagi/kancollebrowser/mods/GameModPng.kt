package app.yahagi.kancollebrowser.mods

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.util.zip.CRC32
import java.util.zip.Inflater

/** One strict PNG validator for imports and read-only software portraits. */
internal object GameModPng {
    const val MAX_BYTES = 64L * 1024 * 1024
    private val signature = byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10)

    fun validateImport(file: File): Long {
        val checked = DataInputStream(file.inputStream().buffered()).use { input ->
            RandomAccessFile(file, "r").use { imageData ->
                inspect(input, file.length()) { offset, buffer, count ->
                    imageData.seek(offset); imageData.readFully(buffer, 0, count)
                }
            }
        }
        // Some exporters append unrelated bytes after a valid IEND. Only the imported copy is normalized.
        if (checked.consumed < file.length()) RandomAccessFile(file, "rw").use { it.setLength(checked.consumed) }
        return checked.decodedSize
    }

    fun validate(bytes: ByteArray): Long {
        checkPng(bytes.size.toLong() <= MAX_BYTES)
        val checked = DataInputStream(ByteArrayInputStream(bytes)).use { input ->
            inspect(input, bytes.size.toLong()) { offset, buffer, count ->
                bytes.copyInto(buffer, 0, offset.toInt(), offset.toInt() + count)
            }
        }
        checkPng(checked.consumed == bytes.size.toLong())
        return checked.decodedSize
    }

    private data class Checked(val decodedSize: Long, val consumed: Long)
    private fun inspect(input: DataInputStream, sourceLength: Long, readAt: (Long, ByteArray, Int) -> Unit): Checked {
        try {
            val signature = ByteArray(8)
            input.readFully(signature)
            checkPng(signature.contentEquals(GameModPng.signature))
            var consumed = 8L
            var width = 0
            var height = 0
            var depth = 0
            var color = -1
            var interlace = -1
            var headerSeen = false
            var paletteSeen = false
            var dataSeen = false
            var dataEnded = false
            var ended = false
            var chunks = 0
            val dataSegments = mutableListOf<Pair<Long, Int>>()
            var compressedSize = 0L
            val buffer = ByteArray(8192)
            while (!ended) {
                checkPng(++chunks <= 100_000 && consumed + 12 <= sourceLength)
                val length = input.readInt()
                checkPng(length >= 0 && consumed + length + 12 <= sourceLength)
                val typeBytes = ByteArray(4)
                input.readFully(typeBytes)
                checkPng(typeBytes.all { it.toInt() in 65..90 || it.toInt() in 97..122 } && typeBytes[2].toInt() in 65..90)
                val type = String(typeBytes, Charsets.US_ASCII)
                checkPng(headerSeen || type == "IHDR")
                if (type == "IHDR") checkPng(!headerSeen && length == 13)
                if (type == "IEND") checkPng(length == 0)
                if (type == "PLTE") checkPng(length in 3..768)
                if (type == "IDAT") {
                    dataSegments.add((consumed + 8) to length)
                    compressedSize += length
                }
                val crc = CRC32().apply { update(typeBytes) }
                var left = length
                val header = if (type == "IHDR") ByteArrayOutputStream() else null
                while (left > 0) {
                    val read = minOf(left, buffer.size)
                    input.readFully(buffer, 0, read)
                    crc.update(buffer, 0, read)
                    if (header != null) header.write(buffer, 0, read)
                    left -= read
                }
                checkPng(crc.value == (input.readInt().toLong() and 0xffffffffL))
                consumed += length + 12L
                when (type) {
                    "IHDR" -> {
                        checkPng(!headerSeen && length == 13)
                        val bytes = ByteBuffer.wrap(header!!.toByteArray())
                        width = bytes.int; height = bytes.int
                        depth = bytes.get().toInt() and 255; color = bytes.get().toInt() and 255
                        val compression = bytes.get().toInt(); val filter = bytes.get().toInt()
                        interlace = bytes.get().toInt()
                        checkPng(width in 1..16_384 && height in 1..16_384 && compression == 0 && filter == 0 && interlace in 0..1)
                        checkPng(when (color) {
                            0 -> depth in listOf(1, 2, 4, 8, 16)
                            2, 4, 6 -> depth in listOf(8, 16)
                            3 -> depth in listOf(1, 2, 4, 8)
                            else -> false
                        })
                        headerSeen = true
                    }
                    "PLTE" -> {
                        checkPng(!paletteSeen && !dataSeen && color != 0 && color != 4 && length in 3..768 && length % 3 == 0)
                        if (color == 3) checkPng(length / 3 <= (1 shl depth))
                        paletteSeen = true
                    }
                    "IDAT" -> { checkPng(!dataEnded && (color != 3 || paletteSeen)); dataSeen = true }
                    "IEND" -> { checkPng(length == 0 && dataSeen); ended = true }
                    else -> checkPng(typeBytes[0].toInt() in 97..122)
                }
                if (dataSeen && type != "IDAT") dataEnded = true
            }
            checkPng(consumed <= sourceLength)
            val channels = when (color) { 0, 3 -> 1; 2 -> 3; 4 -> 2; else -> 4 }
            val passes = if (interlace == 0) listOf(intArrayOf(0, 0, 1, 1)) else listOf(
                intArrayOf(0, 0, 8, 8), intArrayOf(4, 0, 8, 8), intArrayOf(0, 4, 4, 8),
                intArrayOf(2, 0, 4, 4), intArrayOf(0, 2, 2, 4), intArrayOf(1, 0, 2, 2), intArrayOf(0, 1, 1, 2),
            )
            val rows = passes.mapNotNull { pass ->
                val w = if (width <= pass[0]) 0 else (width - pass[0] + pass[2] - 1) / pass[2]
                val h = if (height <= pass[1]) 0 else (height - pass[1] + pass[3] - 1) / pass[3]
                if (w == 0 || h == 0) null else ((w.toLong() * channels * depth + 7) / 8) to h
            }
            val decodedSize = rows.sumOf { (bytes, count) -> (bytes + 1) * count }
            checkPng(decodedSize <= MAX_BYTES)
            val inflater = Inflater()
            try {
                run {
                    val compressedBuffer = ByteArray(8192)
                    var compressedOffset = 0L
                    var segmentIndex = 0
                    var segmentRemaining = 0
                    var compressedRead = 0L
                    fun feed(): Boolean {
                        while (segmentRemaining == 0 && segmentIndex < dataSegments.size) {
                            val (offset, size) = dataSegments[segmentIndex++]
                            compressedOffset = offset
                            segmentRemaining = size
                        }
                        if (segmentRemaining == 0) return false
                        val count = minOf(segmentRemaining, compressedBuffer.size)
                        readAt(compressedOffset, compressedBuffer, count)
                        compressedOffset += count
                        segmentRemaining -= count
                        compressedRead += count
                        inflater.setInput(compressedBuffer, 0, count)
                        return true
                    }
                    fun readDecoded(size: Int): Int {
                        while (true) {
                            val count = inflater.inflate(buffer, 0, size)
                            if (count > 0) return count
                            checkPng(!inflater.finished() && !inflater.needsDictionary() && inflater.needsInput())
                            checkPng(feed())
                        }
                    }
                    for ((bytes, count) in rows) repeat(count) {
                        readDecoded(1)
                        checkPng(buffer[0].toInt() in 0..4)
                        var left = bytes
                        while (left > 0) left -= readDecoded(minOf(left, buffer.size.toLong()).toInt())
                    }
                    while (true) {
                        checkPng(inflater.inflate(buffer) == 0)
                        if (inflater.finished()) break
                        checkPng(!inflater.needsDictionary() && inflater.needsInput() && feed())
                    }
                    checkPng(inflater.remaining == 0 && compressedRead == compressedSize)
                }
            } finally { inflater.end() }
            return Checked(decodedSize, consumed)
        } catch (error: Exception) {
            if (error is GameModException) throw error
            throw GameModException("invalid_png", "PNG 已损坏、被截断或尺寸超出限制。")
        }
    }
    private fun checkPng(valid: Boolean) {
        if (!valid) throw GameModException("invalid_png", "PNG 已损坏、被截断或尺寸超出限制。")
    }
}
