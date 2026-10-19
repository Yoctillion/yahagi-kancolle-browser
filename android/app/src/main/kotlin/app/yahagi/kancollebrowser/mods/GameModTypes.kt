package app.yahagi.kancollebrowser.mods

import java.io.InputStream

class GameModException(val code: String, message: String) : Exception(message)

data class GameModResponse(
    val mimeType: String,
    val statusCode: Int,
    val reasonPhrase: String,
    val headers: Map<String, String>,
    val inputStream: InputStream,
)

/** Opaque transaction handle. Only the repository which created it can consume it. */
class GameModApplyToken internal constructor(internal val id: String)
