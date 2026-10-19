package app.yahagi.kancollebrowser.mods

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class GameModWavTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun `accepts mono and stereo PCM 8 16 24 and 32 bit samples`() {
        for (bits in listOf(8, 16, 24, 32)) for (channels in 1..2) {
            validate(wav(format(bits = bits, channels = channels), ByteArray(channels * bits / 8 * 3)))
        }
    }

    @Test fun `accepts basic float32 including finite samples beyond unit amplitude`() {
        validate(wav(format(tag = 3, bits = 32), floats(0f, -.75f, .5f, 1.25f)))
    }

    @Test fun `accepts extensible PCM containers and smaller valid precision`() {
        for (bits in listOf(8, 16, 24, 32)) {
            validate(wav(format(tag = 0xfffe, bits = bits, subformat = 1), ByteArray(bits / 8 * 4)))
        }
        validate(wav(format(tag = 0xfffe, bits = 32, validBits = 24, subformat = 1), ByteArray(16)))
    }

    @Test fun `accepts real shape extensible float32 and fact zero`() {
        validate(riff(
            chunk("fmt ", format(tag = 0xfffe, bits = 32, subformat = 3)),
            chunk("fact", u32(0)),
            chunk("data", floats(0f, -.5f, .25f, 0f)),
        ))
    }

    @Test fun `accepts consistent nonzero fact and bounded odd metadata chunks`() {
        validate(riff(
            chunk("JUNK", byteArrayOf(1, 2, 3)),
            chunk("fmt ", format()),
            chunk("fact", u32(2)),
            chunk("LIST", byteArrayOf(1, 2, 3, 4, 5)),
            chunk("data", ByteArray(8)),
        ))
    }

    @Test fun `accepts classic PCM with zero sized extension and unspecified channel mask`() {
        validate(wav(format() + u16(0), ByteArray(8)))
        validate(wav(format(tag = 0xfffe, bits = 32, subformat = 3, mask = 0), floats(0f, 0f)))
    }

    @Test fun `rejects disguised audio and unsupported RIFF containers`() {
        invalid("ID3not a WAV stream".toByteArray())
        for (signature in listOf("RF64", "RIFX", "riff")) {
            invalid(wav().also { signature.toByteArray().copyInto(it, 0) })
        }
        invalid(wav().also { "AVI ".toByteArray().copyInto(it, 8) })
    }

    @Test fun `rejects declared RIFF length mismatches and outside trailing bytes`() {
        val valid = wav()
        for (length in listOf(valid.size - 9L, valid.size - 7L, 0xffff_ffffL)) {
            invalid(valid.copyOf().also { u32(length).copyInto(it, 4) })
        }
        invalid(valid + byteArrayOf(0))
    }

    @Test fun `rejects oversized or truncated chunk bodies and headers`() {
        invalid(riff(chunk("fmt ", format()), "data".toByteArray() + u32(0xffff_ffffL)))
        invalid(riff(chunk("fmt ", format()), "dat".toByteArray()))
        val incomplete = chunk("data", ByteArray(8)).dropLast(1).toByteArray()
        invalid(riff(chunk("fmt ", format()), incomplete))
    }

    @Test fun `rejects missing padding after an odd chunk`() {
        val unpadded = chunk("JUNK", byteArrayOf(1)).dropLast(1).toByteArray()
        invalid(riff(unpadded, chunk("fmt ", format()), chunk("data", ByteArray(8))))
    }

    @Test fun `rejects missing or duplicate fmt and data chunks`() {
        val fmt = chunk("fmt ", format())
        val data = chunk("data", ByteArray(8))
        invalid(riff(fmt))
        invalid(riff(data))
        invalid(riff(fmt, fmt, data))
        invalid(riff(fmt, data, fmt))
        invalid(riff(fmt, data, data))
        invalid(riff(data, fmt))
    }

    @Test fun `rejects empty data and incomplete sample frames`() {
        invalid(wav(data = ByteArray(0)))
        invalid(wav(data = ByteArray(7)))
    }

    @Test fun `rejects compressed codecs and unverified float64`() {
        for (tag in listOf(2, 6, 7, 17, 85)) invalid(wav(format(tag = tag)))
        invalid(wav(format(tag = 3, bits = 64), ByteArray(16)))
        invalid(wav(format(tag = 0xfffe, bits = 64, subformat = 3), ByteArray(16)))
    }

    @Test fun `rejects invalid sample rate channel count and container width`() {
        invalid(wav(format(rate = 0)))
        invalid(wav(format(channels = 0)))
        for (bits in listOf(0, 12, 20, 64)) invalid(wav(format(bits = bits)))
    }

    @Test fun `rejects inconsistent byte rate and block alignment`() {
        invalid(wav(format(align = 3)))
        invalid(wav(format(align = 0)))
        invalid(wav(format(byteRate = 0)))
        invalid(wav(format(byteRate = 0xffff_ffffL)))
    }

    @Test fun `rejects incomplete or contradictory format extensions`() {
        invalid(wav(format() + byteArrayOf(0)))
        invalid(wav(format() + u16(8)))
        invalid(wav(format(tag = 0xfffe).copyOf(39)))
        invalid(wav(format(tag = 0xfffe).also { u16(21).copyInto(it, 16) }))
        invalid(wav(format(tag = 0xfffe).also { u16(30).copyInto(it, 16) }))
    }

    @Test fun `rejects unknown or forged extensible subformat GUIDs`() {
        invalid(wav(format(tag = 0xfffe, subformat = 2)))
        invalid(wav(format(tag = 0xfffe).also { it[39] = 0 }))
        invalid(wav(format(tag = 0xfffe).also { it[25] = 1 }))
    }

    @Test fun `rejects invalid extensible precision and mismatched speaker masks`() {
        for (validBits in listOf(0, 17)) invalid(wav(format(tag = 0xfffe, validBits = validBits)))
        invalid(wav(format(tag = 0xfffe, bits = 32, subformat = 3, validBits = 24), ByteArray(8)))
        invalid(wav(format(tag = 0xfffe, mask = 4)))
        invalid(wav(format(tag = 0xfffe, mask = 0x8000_0001L)))
    }

    @Test fun `rejects non finite float samples in basic and extensible streams`() {
        for (tag in listOf(3, 0xfffe)) for (bad in listOf(Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY)) {
            invalid(wav(format(tag = tag, bits = 32, subformat = 3), floats(0f, bad)))
        }
    }

    @Test fun `rejects truncated or inconsistent nonzero fact metadata`() {
        for (fact in listOf(byteArrayOf(0, 0, 0), u32(3))) {
            invalid(riff(chunk("fmt ", format()), chunk("fact", fact), chunk("data", ByteArray(8))))
        }
    }

    @Test fun `rejects unreadable input and files beyond the audio size bound`() {
        val missing = File(temporary.root, "missing.wav")
        assertInvalid { GameModWav.validate(missing) }
        val large = temporary.newFile()
        java.io.RandomAccessFile(large, "rw").use { it.setLength(64L * 1024 * 1024 + 1) }
        assertInvalid { GameModWav.validate(large) }
    }

    @Test fun `validates explicitly supplied real float32 mod fixture`() {
        val path = System.getenv("YAHAGI_REAL_MOD_WAV")
        assumeTrue("Set YAHAGI_REAL_MOD_WAV to run the real package fixture", !path.isNullOrBlank())
        val file = File(path!!)
        assertTrue("The configured WAV fixture must exist", file.isFile)
        GameModWav.validate(file)
    }

    private fun validate(bytes: ByteArray) = GameModWav.validate(temporary.newFile().apply { writeBytes(bytes) })
    private fun invalid(bytes: ByteArray) = assertInvalid { validate(bytes) }
    private fun assertInvalid(block: () -> Unit) {
        try { block(); fail("Invalid WAV was accepted") }
        catch (error: GameModException) { assertEquals("invalid_audio", error.code) }
    }

    private fun format(
        tag: Int = 1, bits: Int = 16, channels: Int = 2, rate: Long = 48000,
        align: Int = channels * bits / 8, byteRate: Long = rate * align,
        validBits: Int = bits, subformat: Int = 1, mask: Long = 3,
    ): ByteArray {
        val base = u16(tag) + u16(channels) + u32(rate) + u32(byteRate) + u16(align) + u16(bits)
        return if (tag != 0xfffe) base else base + u16(22) + u16(validBits) + u32(mask) + u32(subformat.toLong()) +
            byteArrayOf(0, 0, 16, 0, 0x80.toByte(), 0, 0, 0xaa.toByte(), 0, 0x38, 0x9b.toByte(), 0x71)
    }

    private fun wav(fmt: ByteArray = format(), data: ByteArray = ByteArray(8)) =
        riff(chunk("fmt ", fmt), chunk("data", data))
    private fun riff(vararg chunks: ByteArray): ByteArray {
        val body = ByteArrayOutputStream().apply { write("WAVE".toByteArray()); chunks.forEach { write(it) } }.toByteArray()
        return "RIFF".toByteArray() + u32(body.size.toLong()) + body
    }
    private fun chunk(id: String, bytes: ByteArray) =
        id.toByteArray() + u32(bytes.size.toLong()) + bytes + ByteArray(bytes.size and 1)
    private fun u16(value: Int) = byteArrayOf(value.toByte(), (value ushr 8).toByte())
    private fun u32(value: Long) = ByteArray(4) { (value ushr (it * 8)).toByte() }
    private fun floats(vararg values: Float): ByteArray =
        ByteBuffer.allocate(values.size * 4).order(ByteOrder.LITTLE_ENDIAN).apply { values.forEach { putFloat(it) } }.array()
}
