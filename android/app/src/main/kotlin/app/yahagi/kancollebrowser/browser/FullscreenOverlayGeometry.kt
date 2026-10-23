package app.yahagi.kancollebrowser.browser

/** Physical-pixel bounds in the Activity's content root. */
internal data class FullscreenOverlayBounds(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
) {
    val width: Int get() = right - left
    val height: Int get() = bottom - top
}

internal fun fullscreenOverlayContentBounds(
    rootWidth: Int,
    rootHeight: Int,
    requested: FullscreenOverlayBounds? = null,
): FullscreenOverlayBounds {
    val width = rootWidth.coerceAtLeast(0)
    val height = rootHeight.coerceAtLeast(0)
    if (requested == null) return FullscreenOverlayBounds(0, 0, width, height)
    val left = requested.left.coerceIn(0, width)
    val top = requested.top.coerceIn(0, height)
    return FullscreenOverlayBounds(
        left,
        top,
        requested.right.coerceIn(left, width),
        requested.bottom.coerceIn(top, height),
    )
}

internal class FullscreenQuestNoticeGeometry(
    private val content: FullscreenOverlayBounds,
    density: Float,
) {
    private val top = (content.top + (8 * density).toInt()).coerceAtMost(content.bottom)
    val maxWidth = (content.width - (80 * density).toInt())
        .coerceAtLeast((160 * density).toInt().coerceAtMost(content.width))
    val maxHeight = content.bottom - top

    fun place(measuredWidth: Int, measuredHeight: Int): FullscreenOverlayBounds {
        val width = measuredWidth.coerceIn(0, maxWidth)
        val height = measuredHeight.coerceIn(0, maxHeight)
        val left = content.left + (content.width - width) / 2
        return FullscreenOverlayBounds(left, top, left + width, top + height)
    }
}
