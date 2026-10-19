package app.yahagi.kancollebrowser.mods

import android.webkit.WebResourceResponse

/** WebView derives Content-Type from mimeType; supplying it again duplicates the header. */
internal fun GameModResponse.toWebResourceResponse(): WebResourceResponse = try {
    WebResourceResponse(mimeType, if (mimeType == "application/json") "UTF-8" else null, statusCode, reasonPhrase,
        headers.filterKeys { !it.equals("Content-Type", ignoreCase = true) }, inputStream)
} catch (error: Exception) {
    runCatching { inputStream.close() }
    throw error
}
