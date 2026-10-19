package app.yahagi.kancollebrowser.mods

internal data class GameModByteRange(val first: Long, val last: Long) {
    val unsatisfiable get() = first < 0
}

/** Null means ignore the malformed/unsupported Range and send the complete representation. */
internal fun audioByteRange(header: String?, size: Long): GameModByteRange? {
    if (header == null) return null
    val match = Regex("bytes=([0-9]*)-([0-9]*)", RegexOption.IGNORE_CASE).matchEntire(header.trim()) ?: return null
    val start = match.groupValues[1]; val end = match.groupValues[2]
    if (start.isEmpty() && end.isEmpty()) return null
    if (start.isEmpty()) {
        val suffix = end.toLongOrNull() ?: Long.MAX_VALUE
        return if (suffix == 0L || size == 0L) GameModByteRange(-1, -1)
        else GameModByteRange((size - suffix).coerceAtLeast(0), size - 1)
    }
    val first = start.toLongOrNull() ?: return GameModByteRange(-1, -1)
    val last = if (end.isEmpty()) size - 1 else end.toLongOrNull() ?: Long.MAX_VALUE
    return if (first >= size || last < first) GameModByteRange(-1, -1)
    else GameModByteRange(first, last.coerceAtMost(size - 1))
}
