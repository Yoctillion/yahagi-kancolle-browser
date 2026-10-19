package app.yahagi.kancollebrowser.fonts

import java.io.InputStream

/** Owns a provider stream even when opening it races with activity disposal. */
internal class CustomFontImportResources(private val cancelProvider: () -> Unit) {
    private var cancelled = false
    private var input: InputStream? = null

    fun attach(source: InputStream): InputStream {
        val rejected = synchronized(this) {
            if (cancelled) true else { input = source; false }
        }
        if (rejected) {
            runCatching { source.close() }
            throw CustomFontException("activity_destroyed", "The font import was cancelled")
        }
        return source
    }

    fun release(source: InputStream) = synchronized(this) {
        if (input === source) input = null
    }

    fun cancel() {
        val source = synchronized(this) {
            if (cancelled) return
            cancelled = true
            input.also { input = null }
        }
        // Closing the fd interrupts Android's blocking pipe read; thread interruption alone does not.
        runCatching { source?.close() }
        runCatching { cancelProvider() }
    }
}
