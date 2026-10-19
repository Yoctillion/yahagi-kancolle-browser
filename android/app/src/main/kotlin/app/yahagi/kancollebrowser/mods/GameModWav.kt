package app.yahagi.kancollebrowser.mods

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Validates the bounded RIFF structure before a WAV resource is imported. */
internal object GameModWav {
    private const val MAX_AUDIO_BYTES = 64L * 1024 * 1024
    private val subformatSuffix = byteArrayOf(0, 0, 16, 0, 0x80.toByte(), 0, 0, 0xaa.toByte(), 0, 0x38, 0x9b.toByte(), 0x71)

    fun validate(file: File) {
        try {
            RandomAccessFile(file, "r").use { input ->
                val length = input.length()
                checkAudio(length in 12..MAX_AUDIO_BYTES)
                checkAudio(input.readInt() == 0x52494646) // RIFF, little-endian sizes.
                checkAudio(readU32(input) + 8 == length)
                checkAudio(input.readInt() == 0x57415645) // WAVE

                var format: Format? = null
                var frames: Long? = null
                var fact: Long? = null
                var position = 12L
                while (position < length) {
                    checkAudio(length - position >= 8)
                    input.seek(position)
                    val id = input.readInt()
                    val size = readU32(input)
                    val start = position + 8
                    val end = start + size
                    val paddedEnd = end + (size and 1)
                    // All arithmetic is Long, including unsigned RIFF/chunk sizes.
                    checkAudio(end <= length && paddedEnd <= length)
                    when (id) {
                        0x666d7420 -> { // fmt
                            checkAudio(format == null && frames == null)
                            format = readFormat(input, size)
                        }
                        0x64617461 -> { // data
                            val parameters = format
                            checkAudio(parameters != null && frames == null && size > 0)
                            checkAudio(size % parameters!!.blockAlign == 0L)
                            frames = size / parameters.blockAlign
                            if (parameters.floatingPoint) validateFloats(input, size)
                        }
                        0x66616374 -> { // fact; some valid writers leave this count at zero.
                            checkAudio(size >= 4 && fact == null)
                            fact = readU32(input)
                        }
                        // Bounded unknown metadata chunks are skipped, with RIFF word padding.
                    }
                    position = paddedEnd
                }
                checkAudio(position == length && format != null && frames != null)
                checkAudio(fact == null || fact == 0L || fact == frames)
            }
        } catch (error: Exception) {
            if (error is GameModException) throw error
            throw GameModException("invalid_audio", "WAV is truncated, unreadable or unsupported")
        }
    }

    private fun readFormat(input: RandomAccessFile, size: Long): Format {
        checkAudio(size >= 16)
        var tag = readU16(input)
        val channels = readU16(input)
        val rate = readU32(input)
        val byteRate = readU32(input)
        val blockAlign = readU16(input)
        val bits = readU16(input)
        // Voice resources use mono/stereo; avoid promising unverified channel layouts.
        checkAudio(channels in 1..2 && rate in 1..384000)
        var extensionSize = 0
        if (size > 16) {
            checkAudio(size >= 18)
            extensionSize = readU16(input)
            checkAudio(extensionSize.toLong() <= size - 18)
        }
        if (tag == 0xfffe) {
            checkAudio(size >= 40 && extensionSize >= 22)
            val validBits = readU16(input)
            val mask = readU32(input)
            val subformat = readU32(input)
            val suffix = ByteArray(12).also(input::readFully)
            checkAudio(subformat in listOf(1L, 3L) && suffix.contentEquals(subformatSuffix))
            tag = subformat.toInt()
            checkAudio(validBits in 1..bits && (tag != 3 || validBits == 32))
            checkAudio(mask == 0L || (mask and 0x3ffffL.inv() == 0L && java.lang.Long.bitCount(mask) == channels))
        }
        checkAudio((tag == 1 && bits in listOf(8, 16, 24, 32)) || (tag == 3 && bits == 32))
        checkAudio(blockAlign == channels * (bits / 8))
        checkAudio(byteRate == rate * blockAlign)
        return Format(blockAlign, tag == 3)
    }

    private fun validateFloats(input: RandomAccessFile, size: Long) {
        val bytes = ByteArray(minOf(size, 16L * 1024).toInt())
        var remaining = size
        while (remaining > 0) {
            val count = minOf(remaining, bytes.size.toLong()).toInt()
            input.readFully(bytes, 0, count)
            val samples = ByteBuffer.wrap(bytes, 0, count).order(ByteOrder.LITTLE_ENDIAN)
            while (samples.remaining() >= 4) {
                val sample = samples.float
                checkAudio(!sample.isNaN() && !sample.isInfinite())
            }
            remaining -= count
        }
    }

    private fun readU16(input: RandomAccessFile) = input.readUnsignedByte() or (input.readUnsignedByte() shl 8)

    private fun readU32(input: RandomAccessFile): Long {
        var result = 0L
        repeat(4) { result = result or (input.readUnsignedByte().toLong() shl (it * 8)) }
        return result
    }

    private fun checkAudio(condition: Boolean) {
        if (!condition) throw GameModException("invalid_audio", "WAV structure or sample format is invalid or unsupported")
    }

    private data class Format(val blockAlign: Int, val floatingPoint: Boolean)
}
