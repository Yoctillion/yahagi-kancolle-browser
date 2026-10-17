package app.yahagi.kancollebrowser.backup

import java.io.InputStream

/** Verifies a document without keeping another complete archive in memory. */
internal object BackupDocumentReadback {
    fun matches(input: InputStream, expected: ByteArray): Boolean {
        val chunk = ByteArray(8192)
        var offset = 0
        while (offset < expected.size) {
            val count = input.read(chunk, 0, minOf(chunk.size, expected.size - offset))
            if (count < 0) return false
            if (count == 0) {
                val next = input.read()
                if (next < 0 || next.toByte() != expected[offset++]) return false
                continue
            }
            for (index in 0 until count) {
                if (chunk[index] != expected[offset + index]) return false
            }
            offset += count
        }
        return input.read() < 0
    }
}
