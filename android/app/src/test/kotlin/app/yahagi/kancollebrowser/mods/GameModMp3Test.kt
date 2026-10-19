package app.yahagi.kancollebrowser.mods

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class GameModMp3Test {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun `accepts complete layer III chains for MPEG 1 2 and 2 point 5`() {
        for (version in listOf(3, 2, 0)) for (rate in 0..2) {
            validate(frame(version = version, rate = rate) + frame(version = version, rate = rate))
        }
    }

    @Test fun `accepts variable bitrate frames with consistent stream parameters`() {
        validate(frame(bitrate = 9) + frame(bitrate = 11) + frame(bitrate = 14))
    }

    @Test fun `skips bounded ID3 version 2 and version 1 metadata`() {
        val leading = byteArrayOf(73, 68, 51, 3, 0, 0, 0, 0, 0, 5) + ByteArray(5)
        val trailing = byteArrayOf(84, 65, 71) + ByteArray(125)
        validate(leading + frame() + frame() + trailing)
    }

    @Test fun `skips ID3 version 4 metadata with a footer`() {
        val leading = byteArrayOf(73, 68, 51, 4, 0, 16, 0, 0, 0, 5) + ByteArray(5)
        val footer = byteArrayOf(51, 68, 73, 4, 0, 16, 0, 0, 0, 5)
        validate(leading + footer + frame() + frame())
    }

    @Test fun `does not mistake TAG inside the last audio frame for trailing metadata`() {
        val data = frame() + frame()
        byteArrayOf(84, 65, 71).copyInto(data, data.size - 128)
        validate(data)
    }

    @Test fun `rejects WAV or text disguised as MP3`() {
        invalid("RIFF1234WAVEfmt ".toByteArray())
        invalid("This is not an audio stream".toByteArray())
    }

    @Test fun `rejects a truncated frame body`() {
        invalid((frame() + frame()).dropLast(1).toByteArray())
    }

    @Test fun `rejects a truncated frame header`() {
        invalid(frame() + frame().copyOf(3))
    }

    @Test fun `rejects changing sample rate inside one stream`() {
        invalid(frame(rate = 0) + frame(rate = 1))
    }

    @Test fun `rejects reserved MPEG version layer bitrate or sample rate`() {
        for ((offset, mask) in listOf(1 to 0x10, 1 to 0x04, 2 to 0xe0, 2 to 0x08)) {
            val data = frame() + frame()
            data[offset] = (data[offset].toInt() xor mask).toByte()
            invalid(data)
        }
    }

    @Test fun `rejects ID3 size extending past the file`() {
        invalid(byteArrayOf(73, 68, 51, 3, 0, 0, 0, 0, 0, 127) + frame().copyOf(10))
    }

    @Test fun `rejects non synchsafe ID3 size bytes`() {
        invalid(byteArrayOf(73, 68, 51, 3, 0, 0, 0, 0, 0, -128) + frame() + frame())
    }

    @Test fun `rejects a tag without audio and a lone plausible frame`() {
        invalid(byteArrayOf(73, 68, 51, 3, 0, 0, 0, 0, 0, 0))
        invalid(frame())
    }

    @Test fun `rejects non frame trailing data`() {
        invalid(frame() + frame() + byteArrayOf(1, 2, 3, 4))
    }

    @Test fun `validates real mod MP3 fixtures when explicitly supplied`() {
        val path = System.getenv("YAHAGI_REAL_MOD_AUDIO_DIR") ?: return
        val files = File(path).walkTopDown().filter { it.isFile && it.extension.equals("mp3", true) }.toList()
        assertTrue("The selected fixture directory must contain MP3 files", files.isNotEmpty())
        files.forEach(GameModMp3::validate)
    }

    private fun validate(bytes: ByteArray) = GameModMp3.validate(temporary.newFile().apply { writeBytes(bytes) })

    private fun invalid(bytes: ByteArray) {
        try {
            validate(bytes)
            fail("Invalid MP3 was accepted")
        } catch (error: GameModException) {
            assertEquals("invalid_audio", error.code)
        }
    }

    private fun frame(version: Int = 3, rate: Int = 1, bitrate: Int = 14): ByteArray {
        val sampleRate = intArrayOf(44100, 48000, 32000)[rate] / when (version) { 3 -> 1; 2 -> 2; else -> 4 }
        val rates = if (version == 3) intArrayOf(0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320)
            else intArrayOf(0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160)
        val size = (if (version == 3) 144000 else 72000) * rates[bitrate] / sampleRate
        val header = 0xffe00000.toInt() or (version shl 19) or (1 shl 17) or (1 shl 16) or (bitrate shl 12) or (rate shl 10)
        return ByteArray(size).also { data -> repeat(4) { data[it] = (header ushr (24 - it * 8)).toByte() } }
    }
}
