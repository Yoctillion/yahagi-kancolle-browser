package app.yahagi.kancollebrowser.mods

import java.io.File
import java.io.RandomAccessFile

/** Bounded frame validation; no codec, Android API or full audio allocation is needed. */
internal object GameModMp3 {
    private const val MAX_AUDIO_BYTES = 64L * 1024 * 1024
    private val mpeg1Bitrates = intArrayOf(0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320)
    private val mpeg2Bitrates = intArrayOf(0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160)

    fun validate(file: File) {
        try {
            RandomAccessFile(file, "r").use { input ->
                val length = input.length()
                checkAudio(length in 8..MAX_AUDIO_BYTES)
                val end = length

                var position = 0L
                while (position + 3 <= end) {
                    input.seek(position)
                    if (input.read() != 'I'.code || input.read() != 'D'.code || input.read() != '3'.code) break
                    checkAudio(position + 10 <= end)
                    input.seek(position)
                    val tag = ByteArray(10).also(input::readFully)
                    checkAudio(tag[3].toInt() in 2..4 && tag[4].toInt() != -1)
                    checkAudio((6..9).all { tag[it].toInt() and 0x80 == 0 })
                    val size = (6..9).fold(0L) { total, index -> (total shl 7) or tag[index].toLong() }
                    position += 10 + size
                    checkAudio(position <= end)
                    if (tag[3].toInt() == 4 && tag[5].toInt() and 0x10 != 0) {
                        checkAudio(position + 10 <= end)
                        input.seek(position)
                        val footer = ByteArray(10).also(input::readFully)
                        checkAudio(footer[0] == 51.toByte() && footer[1] == 68.toByte() && footer[2] == 73.toByte())
                        checkAudio((3..9).all { footer[it] == tag[it] })
                        position += 10
                    }
                }

                var streamVersion = -1
                var streamRate = -1
                var frameCount = 0
                while (position < end) {
                    // A trailing ID3v1 tag must start at a frame boundary, not inside audio data.
                    if (end - position == 128L) {
                        input.seek(position)
                        if (input.read() == 'T'.code && input.read() == 'A'.code && input.read() == 'G'.code) {
                            position = end
                            break
                        }
                    }
                    checkAudio(position + 4 <= end)
                    input.seek(position)
                    val header = input.readInt()
                    checkAudio(header ushr 21 == 0x7ff)
                    val version = header ushr 19 and 3
                    val layer = header ushr 17 and 3
                    val bitrateIndex = header ushr 12 and 15
                    val rateIndex = header ushr 10 and 3
                    val padding = header ushr 9 and 1
                    checkAudio(version != 1 && layer == 1 && bitrateIndex in 1..14 && rateIndex != 3)
                    checkAudio(header and 3 != 2) // Reserved emphasis is not a valid MPEG audio header.
                    val rate = intArrayOf(44100, 48000, 32000)[rateIndex] / when (version) { 3 -> 1; 2 -> 2; else -> 4 }
                    if (streamVersion == -1) { streamVersion = version; streamRate = rate }
                    checkAudio(version == streamVersion && rate == streamRate)
                    val bitrate = (if (version == 3) mpeg1Bitrates else mpeg2Bitrates)[bitrateIndex]
                    val frameBytes = (if (version == 3) 144000 else 72000) * bitrate / rate + padding
                    checkAudio(frameBytes >= 4 && position + frameBytes <= end)
                    position += frameBytes
                    frameCount++
                }
                // Two complete consecutive frames avoid treating one accidental sync word as audio.
                checkAudio(position == end && frameCount >= 2)
            }
        } catch (error: Exception) {
            if (error is GameModException) throw error
            throw GameModException("invalid_audio", "MP3 is truncated, unreadable or unsupported")
        }
    }

    private fun checkAudio(condition: Boolean) {
        if (!condition) throw GameModException("invalid_audio", "MP3 frame structure is invalid or truncated")
    }
}
