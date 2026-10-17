package app.yahagi.kancollebrowser.backup

import android.os.Debug
import android.util.Base64
import android.util.Log
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.yahagi.kancollebrowser.MainActivity
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.zip.GZIPOutputStream
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BackupArchiveOwnerTest {
    private lateinit var scenario: ActivityScenario<MainActivity>
    private lateinit var handler: RecordBackupHandler
    private val ownerMethod = RecordBackupHandler::class.java
        .getDeclaredMethod("archiveMemberId", ByteArray::class.java).apply { isAccessible = true }

    @Before fun openHandler() {
        scenario = ActivityScenario.launch(MainActivity::class.java)
        scenario.onActivity { handler = RecordBackupHandler(it, { _, _ -> }) }
    }

    @After fun closeHandler() {
        scenario.onActivity { handler.dispose() }
        scenario.close()
    }

    @Test fun readsOwnerBeforeOrAfterEmptyArchiveData() {
        assertEquals(7, owner(archive("""{"memberId":7,"tables":{},"compositions":[]}""")))
        assertEquals(9, owner(archive("""{"tables":{},"compositions":[],"memberId":9}""")))
        assertEquals(9, owner(archive("""{"memberId":7,"tables":{},"memberId":9}""")))
        assertNull(owner(archive("""{"memberId":7,"memberId":null}""")))
    }

    @Test fun rejectsMalformedJsonAfterAnOtherwiseValidOwner() {
        assertNull(owner(archive("""{"memberId":7,"tables":[}""")))
        assertNull(owner(archive("""{"memberId":7} {"memberId":9}""")))
    }

    @Test fun rejectsInvalidOwnersAndMissingOwners() {
        for (id in listOf("0", "-7", "1.5", "\"7\"", "2147483648", "null")) {
            assertNull("Invalid owner $id", owner(archive("""{"memberId":$id,"tables":{}}""")))
        }
        assertNull(owner(archive("""{"tables":{},"compositions":[]}""")))
    }

    @Test fun rejectsMalformedSkippedStringsAndUtf8() {
        assertNull(owner(archive("""{"memberId":7,"tables":{"x":"bad\q"}}""")))
        assertNull(owner(archive("""{"memberId":7,"tables":{"x":"bad\uZZZZ"}}""")))
        assertNull(owner(archive("""{"memberId":7,"tables":{"x":"bad""" + '\u0001' + """value"}}""")))
        val invalidUtf8 = """{"memberId":7,"tables":{"x":"""".toByteArray() +
            byteArrayOf(0xc3.toByte(), 0x28) + """"}}""".toByteArray()
        assertNull(owner(envelope(compressed(invalidUtf8))))
    }

    @Test fun rejectsChecksumMismatchAndBrokenGzipTrailer() {
        val valid = archive("""{"memberId":7}""")
        val envelope = JSONObject(valid.toString(Charsets.UTF_8))
        envelope.put("sha256", "0".repeat(64))
        assertNull(owner(envelope.toString().toByteArray()))
        val compressed = compressed("""{"memberId":7}""".toByteArray()).also {
            it[it.lastIndex - 4] = (it[it.lastIndex - 4].toInt() xor 1).toByte()
        }
        assertNull(owner(envelope(compressed)))
    }

    @Test fun ownerCheckDoesNotAllocateTheUncompressedTables() {
        val bytes = largeArchive(8 * 1024 * 1024, ownerAtEnd = false)
        owner(archive("""{"memberId":7}"""))
        val start = Debug.getRuntimeStat("art.gc.bytes-allocated").toLong()
        assertEquals(7, owner(bytes))
        val allocated = Debug.getRuntimeStat("art.gc.bytes-allocated").toLong() - start
        Log.i("BackupMemoryProbe", "BACKUP_OWNER_ALLOCATION plain=8388608 archive=${bytes.size} allocated=$allocated")
        assertTrue("Owner check allocated $allocated bytes for an 8 MiB table value", allocated < 1024 * 1024)
    }

    @Test fun readsOwnerFollowingLargeTables() {
        assertEquals(7, owner(largeArchive(8 * 1024 * 1024, ownerAtEnd = true)))
    }

    @Test fun rejectsArchiveBeyondTheInflatedSizeLimit() {
        assertNull(owner(largeArchive(250 * 1024 * 1024, ownerAtEnd = false)))
    }

    private fun largeArchive(tableValueBytes: Int, ownerAtEnd: Boolean): ByteArray {
        val output = ByteArrayOutputStream()
        GZIPOutputStream(output).use { gzip ->
            gzip.write((if (ownerAtEnd) "{" else "{\"memberId\":7,").toByteArray())
            gzip.write(""""tables":{"logs":[{"detail":"""".toByteArray())
            val chunk = ByteArray(8192) { 'a'.code.toByte() }
            repeat(tableValueBytes / chunk.size) { gzip.write(chunk) }
            gzip.write(chunk, 0, tableValueBytes % chunk.size)
            gzip.write(""""}]},"compositions":[]""".toByteArray())
            gzip.write((if (ownerAtEnd) ",\"memberId\":7}" else "}").toByteArray())
        }
        return envelope(output.toByteArray())
    }

    private fun owner(bytes: ByteArray) = ownerMethod.invoke(handler, bytes) as Int?

    private fun archive(json: String) = envelope(compressed(json.toByteArray()))

    private fun compressed(bytes: ByteArray): ByteArray {
        val output = ByteArrayOutputStream()
        GZIPOutputStream(output).use { it.write(bytes) }
        return output.toByteArray()
    }

    private fun envelope(compressed: ByteArray): ByteArray = JSONObject().apply {
        put("format", "yahagi-record-backup")
        put("version", 1)
        put("sha256", MessageDigest.getInstance("SHA-256").digest(compressed)
            .joinToString("") { "%02x".format(it.toInt() and 0xff) })
        put("payload", Base64.encodeToString(compressed, Base64.NO_WRAP))
    }.toString().toByteArray()
}
