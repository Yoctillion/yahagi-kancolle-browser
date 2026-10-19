package app.yahagi.kancollebrowser.fonts

import java.io.ByteArrayInputStream
import java.io.InputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import org.junit.Assert.*
import org.junit.Test

class CustomFontImportResourcesTest {
    @Test fun `cancellation closes an attached provider stream and releases its blocked reader`() {
        val reading = CountDownLatch(1)
        val closed = CountDownLatch(1)
        val stream = object : InputStream() {
            override fun read(): Int {
                reading.countDown()
                while (true) {
                    try { closed.await(); return -1 } catch (_: InterruptedException) {}
                }
            }
            override fun close() { closed.countDown() }
        }
        val providerCancelled = AtomicBoolean()
        val resources = CustomFontImportResources { providerCancelled.set(true) }
        resources.attach(stream)
        val worker = Executors.newSingleThreadExecutor()
        try {
            val result = worker.submit<Int> { stream.read() }
            assertTrue(reading.await(3, TimeUnit.SECONDS))
            resources.cancel()
            assertEquals(-1, result.get(3, TimeUnit.SECONDS))
            assertTrue(providerCancelled.get())
        } finally {
            stream.close()
            worker.shutdownNow()
        }
    }

    @Test fun `a provider stream delivered after cancellation is closed and rejected`() {
        var closed = false
        val stream = object : ByteArrayInputStream(byteArrayOf()) {
            override fun close() { closed = true }
        }
        val resources = CustomFontImportResources {}
        resources.cancel()
        try {
            resources.attach(stream)
            fail("Late provider result must not survive activity disposal")
        } catch (error: CustomFontException) {
            assertEquals("activity_destroyed", error.code)
        }
        assertTrue(closed)
    }

    @Test fun `completed source is released and provider cancellation is idempotent`() {
        var closes = 0
        var cancellations = 0
        val stream = object : ByteArrayInputStream(byteArrayOf()) {
            override fun close() { closes++ }
        }
        val resources = CustomFontImportResources { cancellations++ }
        resources.attach(stream)
        resources.release(stream)
        resources.cancel()
        resources.cancel()
        assertEquals(0, closes)
        assertEquals(1, cancellations)
    }

}
