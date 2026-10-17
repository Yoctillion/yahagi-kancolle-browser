package app.yahagi.kancollebrowser.backup

import android.util.Base64
import com.google.gson.Strictness
import com.google.gson.stream.JsonReader
import com.google.gson.stream.JsonToken
import java.io.ByteArrayInputStream
import java.io.FilterInputStream
import java.io.FilterReader
import java.io.InputStream
import java.io.InputStreamReader
import java.io.Reader
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.zip.GZIPInputStream
import org.json.JSONObject

/** Reads an archive's owner without materializing all of its logbook rows. */
internal object BackupArchiveOwner {
    private const val MAX_ARCHIVE_BYTES = 100 * 1024 * 1024
    private const val MAX_PLAIN_BYTES = 250L * 1024 * 1024
    private val positiveInteger = Regex("[1-9][0-9]*")

    fun memberId(bytes: ByteArray): Int? = runCatching {
        require(bytes.size <= MAX_ARCHIVE_BYTES) { "Backup is too large" }
        val envelope = JSONObject(bytes.toString(Charsets.UTF_8))
        require(envelope.optString("format") == "yahagi-record-backup" &&
            envelope.optInt("version") == 1) { "Unsupported backup format" }
        val compressed = Base64.decode(envelope.getString("payload"), Base64.DEFAULT)
        val digest = MessageDigest.getInstance("SHA-256").digest(compressed)
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        require(digest == envelope.getString("sha256")) { "Backup checksum mismatch" }
        val utf8 = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        val plain = LimitedInputStream(
            GZIPInputStream(ByteArrayInputStream(compressed)), MAX_PLAIN_BYTES,
        )
        JsonReader(StrictStringReader(InputStreamReader(plain, utf8))).apply {
            strictness = Strictness.STRICT
        }.use { reader ->
            var owner: Int? = null
            reader.beginObject()
            while (reader.hasNext()) {
                if (reader.nextName() == "memberId") {
                    // Match Dart's positive integer account contract. As with
                    // JSONObject/jsonDecode, the last duplicate key wins.
                    if (reader.peek() == JsonToken.NUMBER) {
                        val number = reader.nextString()
                        owner = number.takeIf(positiveInteger::matches)?.toIntOrNull()
                    } else {
                        reader.skipValue()
                        owner = null
                    }
                } else {
                    // JsonReader skips strings and nested data without making
                    // a String/JSONObject for every table, row, or value.
                    reader.skipValue()
                }
            }
            reader.endObject()
            // Read through EOF: malformed tails, extra JSON, gzip CRC/trailer
            // failures, and over-limit tails must not authorize an overwrite.
            require(reader.peek() == JsonToken.END_DOCUMENT) { "Invalid backup content" }
            owner
        }
    }.getOrNull()

    // Gson 2.11 skips quoted values without allocating them, but that skip
    // path permits raw control characters even with Strictness.STRICT.
    private class StrictStringReader(input: Reader) : FilterReader(input) {
        private var quoted = false
        private var escaped = false

        override fun read(): Int = `in`.read().also { value ->
            if (value >= 0) checkCharacter(value.toChar())
        }

        override fun read(buffer: CharArray, offset: Int, length: Int): Int =
            `in`.read(buffer, offset, length).also { count ->
                for (index in offset until offset + count) checkCharacter(buffer[index])
            }

        private fun checkCharacter(character: Char) {
            if (!quoted) {
                if (character == '"') quoted = true
                return
            }
            require(character >= ' ') { "Unescaped control character in backup" }
            when {
                escaped -> escaped = false
                character == '\\' -> escaped = true
                character == '"' -> quoted = false
            }
        }
    }

    private class LimitedInputStream(input: InputStream, private var remaining: Long) :
        FilterInputStream(input) {
        override fun read(): Int {
            val value = `in`.read()
            if (value >= 0) {
                require(remaining > 0) { "Backup is too large" }
                remaining--
            }
            return value
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            val count = `in`.read(buffer, offset, minOf(length.toLong(), remaining + 1).toInt())
            if (count > 0) {
                require(count <= remaining) { "Backup is too large" }
                remaining -= count
            }
            return count
        }
    }
}
