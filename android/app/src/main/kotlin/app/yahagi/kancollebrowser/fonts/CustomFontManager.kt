package app.yahagi.kancollebrowser.fonts

import android.app.Activity
import android.content.Intent
import android.graphics.Typeface
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** SAF/font decoding stays native; previews return a bounded PNG instead of registering a font. */
internal class CustomFontManager(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "app.yahagi.kancollebrowser/custom_fonts"
        const val PICK_FONT_REQUEST = 2408
        private val repositories = mutableMapOf<String, CustomFontRepository>()
        @Synchronized private fun repositoryFor(root: File) = repositories.getOrPut(root.absolutePath) {
            CustomFontRepository(root) { file ->
                val typeface = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Typeface.Builder(file).build()
                } else {
                    Typeface.createFromFile(file)
                }
                if (typeface == null || typeface === Typeface.DEFAULT) {
                    throw CustomFontException("invalid_font", "The selected font cannot be loaded")
                }
            }
        }
    }

    private val resolver = activity.applicationContext.contentResolver
    private val repository = repositoryFor(File(activity.applicationContext.filesDir, "custom_fonts"))
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val replies = mutableSetOf<Reply>()
    private var picker: Reply? = null
    private var activeImport: Reply? = null
    private var activePreview: Reply? = null
    private val previewGate = CustomFontPreviewGate()
    private var importResources: CustomFontImportResources? = null
    @Volatile private var disposed = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = Reply(result).also { replies.add(it) }
        if (disposed) { reply.error("activity_destroyed", "The activity is no longer available"); return }
        when (call.method) {
            "importFont" -> pickFont(reply)
            "renderPreview" -> renderPreview(call.arguments, reply)
            "removeFont" -> {
                val id = (call.arguments as? Map<*, *>)?.get("id") as? String
                if (id == null) reply.error("invalid_font_id", "Missing custom font identifier")
                else runIo(reply) { repository.removeFont(id); null }
            }
            "pruneFonts" -> {
                val ids = (call.arguments as? Map<*, *>)?.get("ids") as? List<*>
                if (ids == null || ids.any { it !is String }) {
                    reply.error("invalid_font_id", "Missing custom font identifiers")
                } else if (picker != null || activeImport != null) {
                    reply.error("picker_busy", "A font import is already in progress")
                } else {
                    val keepIds = ids.filterIsInstance<String>().toSet()
                    runIo(reply) { repository.pruneUnused(keepIds); null }
                }
            }
            else -> reply.notImplemented()
        }
    }

    private fun renderPreview(arguments: Any?, reply: Reply) {
        val request = try { CustomFontPreviewRequest.fromArguments(arguments) }
        catch (error: CustomFontException) { reply.failure(error); return }
        if (!previewGate.tryAcquire()) {
            reply.error("preview_busy", "A font preview is already in progress")
            return
        }
        activePreview = reply
        runIo(reply) {
            repository.withFontFile(request.id) { file ->
                CustomFontPreviewRenderer.render(file, request) { disposed }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun pickFont(reply: Reply) {
        if (picker != null || activeImport != null) {
            reply.error("picker_busy", "A font import is already in progress")
            return
        }
        picker = reply
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*" // Providers often report font files as application/octet-stream.
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }, PICK_FONT_REQUEST)
        } catch (error: Exception) { reply.failure(error) }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_FONT_REQUEST) return false
        val reply = picker ?: return true
        picker = null
        val uri = data?.data?.takeIf { resultCode == Activity.RESULT_OK }
        if (uri == null) { reply.success(null); return true }
        activeImport = reply
        val cancellation = CancellationSignal()
        val resources = CustomFontImportResources { cancellation.cancel() }
        importResources = resources
        runIo(reply) {
            val name = runCatching {
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null, cancellation)?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
            }.getOrNull() ?: "Custom font"
            val descriptor = resolver.openAssetFileDescriptor(uri, "r", cancellation)
                ?: throw CustomFontException("font_unreadable", "Unable to read the selected font")
            val input = try {
                resources.attach(descriptor.createInputStream())
            } catch (error: Exception) {
                runCatching { descriptor.close() }
                throw error
            }
            try {
                repository.importFont(input, name) { disposed || Thread.currentThread().isInterrupted }.toMap()
            } finally {
                resources.release(input)
            }
        }
        return true
    }

    private fun runIo(reply: Reply, operation: () -> Any?) {
        try {
            worker.execute {
                try {
                    if (disposed) throw CustomFontException("activity_destroyed", "The font operation was cancelled")
                    val value = operation()
                    main.post {
                        if (disposed) reply.error("activity_destroyed", "The font operation was cancelled")
                        else reply.success(value)
                    }
                } catch (error: Exception) { main.post { reply.failure(error) } }
            }
        } catch (error: Exception) { reply.failure(error) }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        replies.toList().forEach { it.error("activity_destroyed", "The font operation was cancelled") }
        importResources?.cancel()
        importResources = null
        worker.shutdownNow()
    }

    private inner class Reply(private val result: MethodChannel.Result) {
        private val completed = AtomicBoolean(false)
        private fun complete(action: () -> Unit) {
            if (!completed.compareAndSet(false, true)) return
            replies.remove(this)
            if (picker === this) picker = null
            if (activePreview === this) {
                activePreview = null
                previewGate.release()
            }
            if (activeImport === this) {
                activeImport = null
                if (!disposed) importResources = null
            }
            action()
        }
        fun success(value: Any?) = complete { result.success(value) }
        fun error(code: String, message: String?) = complete { result.error(code, message, null) }
        fun notImplemented() = complete { result.notImplemented() }
        fun failure(error: Exception) = when (error) {
            is CustomFontException -> error(error.code, error.message)
            else -> error("font_import_failed", "Unable to complete the font operation")
        }
    }
}
