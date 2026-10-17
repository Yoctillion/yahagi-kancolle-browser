package app.yahagi.kancollebrowser.backup

import android.os.Process
import androidx.core.content.FileProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.Properties
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Explicit host-orchestrated probe; unconfigured normal test runs skip it. */
@RunWith(AndroidJUnit4::class)
class BackupExportProcessDeathProbe {
    private fun expected() = ByteArray(64 * 1024) { (it % 251).toByte() }

    @Test fun prepare() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("backupExportProbe") == "prepare")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val fixture = File(context.filesDir, "record-backup-process-death-probe.properties")
        check(!fixture.exists()) { "A previous probe fixture is retained; verify it before preparing another" }
        val directory = File(context.cacheDir, "record-backup-share/process-death-${UUID.randomUUID()}")
        check(directory.mkdirs())
        val target = File(directory, "process-death-probe.yhb").apply { writeBytes(byteArrayOf()) }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.diagnostics", target)
        val store = PendingBackupExportStore(File(context.filesDir, "record-backup-exports"))
        val entry = store.stage("process-death-probe.yhb", expected())
        store.select(entry.token, uri.toString(), 0)
        Properties().apply {
            setProperty("token", entry.token)
            setProperty("path", target.absolutePath)
            setProperty("preparedPid", Process.myPid().toString())
        }.also { properties -> fixture.outputStream().use { properties.store(it, null) } }
        assertEquals(0L, target.length())
        assertFalse(store.get(entry.token)!!.verified)
    }

    @Test fun verify() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("backupExportProbe") == "verify")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val fixture = File(context.filesDir, "record-backup-process-death-probe.properties")
        val properties = Properties().apply { fixture.inputStream().use { load(it) } }
        assertNotEquals(properties.getProperty("preparedPid"), Process.myPid().toString())
        val store = PendingBackupExportStore(File(context.filesDir, "record-backup-exports"))
        val token = properties.getProperty("token")
        assertTrue("MainActivity startup must recover the transaction", store.get(token)?.verified == true)
        assertArrayEquals(expected(), File(properties.getProperty("path")).readBytes())
        store.complete(token)
        // Keep the fixture and exact resulting bytes for host-side inspection.
    }
}
