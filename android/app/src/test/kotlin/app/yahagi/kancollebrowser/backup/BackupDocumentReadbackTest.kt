package app.yahagi.kancollebrowser.backup

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import org.junit.Assert.*
import org.junit.Test

class BackupDocumentReadbackTest {
    @Test fun acceptsAnExactDocumentEvenWhenTheProviderReturnsShortReads() {
        val expected = ByteArray(31_769) { (it * 31).toByte() }
        val input = object : ByteArrayInputStream(expected) {
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
                super.read(buffer, offset, minOf(length, 7))
        }
        assertTrue(BackupDocumentReadback.matches(input, expected))
    }

    @Test fun rejectsTruncatedExtendedAndChangedDocuments() {
        val expected = ByteArray(20_000) { it.toByte() }
        assertFalse(BackupDocumentReadback.matches(ByteArrayInputStream(expected.copyOf(19_999)), expected))
        assertFalse(BackupDocumentReadback.matches(ByteArrayInputStream(expected + byteArrayOf(1)), expected))
        val changed = expected.copyOf().apply { this[8192] = (this[8192] + 1).toByte() }
        assertFalse(BackupDocumentReadback.matches(ByteArrayInputStream(changed), expected))
        assertTrue(BackupDocumentReadback.matches(ByteArrayInputStream(byteArrayOf()), byteArrayOf()))
        assertFalse(BackupDocumentReadback.matches(ByteArrayInputStream(byteArrayOf(1)), byteArrayOf()))
    }

    @Test fun providerReadFailureIsNotReportedAsAMismatch() {
        val failure = IOException("Read permission was revoked")
        val input = object : InputStream() {
            override fun read(): Int = throw failure
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int = throw failure
        }
        assertSame(failure, assertThrows(IOException::class.java) {
            BackupDocumentReadback.matches(input, byteArrayOf(1))
        })
    }

    @Test fun verificationAllocationDoesNotGrowWithTheDocument() {
        // Android's compile API excludes JVM management classes; invoke the
        // host-JVM allocation counter reflectively without an app dependency.
        val allocation = Class.forName("java.lang.management.ManagementFactory")
            .getMethod("getThreadMXBean").invoke(null)
        val counter = Class.forName("com.sun.management.ThreadMXBean")
        counter.getMethod("setThreadAllocatedMemoryEnabled", Boolean::class.javaPrimitiveType)
            .invoke(allocation, true)
        val getAllocated = counter.getMethod("getThreadAllocatedBytes", Long::class.javaPrimitiveType)
        fun allocated() = getAllocated.invoke(allocation, Thread.currentThread().id) as Long
        val expected = ByteArray(16 * 1024 * 1024) { (it * 31).toByte() }
        repeat(3) { assertTrue(BackupDocumentReadback.matches(ByteArrayInputStream(expected), expected)) }
        val oldStart = allocated()
        assertTrue(legacyReadback(ByteArrayInputStream(expected)).contentEquals(expected))
        val oldBytes = allocated() - oldStart
        val start = allocated()
        assertTrue(BackupDocumentReadback.matches(ByteArrayInputStream(expected), expected))
        val allocatedBytes = allocated() - start
        println("BACKUP_READBACK_ALLOCATION document=${expected.size} legacy=$oldBytes current=$allocatedBytes")
        assertTrue("Verification allocated $allocatedBytes bytes for a ${expected.size}-byte document",
            allocatedBytes < 256 * 1024)
    }

    // The handler's prior readDocument(...).contentEquals(expected) path.
    private fun legacyReadback(input: InputStream): ByteArray {
        val output = ByteArrayOutputStream()
        val chunk = ByteArray(8192)
        while (true) {
            val count = input.read(chunk)
            if (count < 0) break
            output.write(chunk, 0, count)
        }
        return output.toByteArray()
    }
}
