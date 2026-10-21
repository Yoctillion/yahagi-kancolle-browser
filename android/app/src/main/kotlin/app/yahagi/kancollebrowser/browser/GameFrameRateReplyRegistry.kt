package app.yahagi.kancollebrowser.browser

/** Bounded document channels. All calls stay on the WebView/UI thread. */
internal class GameFrameRateReplyRegistry<T : Any>(
    private val maxProxies: Int = 32,
    private val maxPerOrigin: Int = 8,
) {
    init {
        require(maxProxies > 0 && maxPerOrigin in 1..maxProxies)
    }

    private class Entry<T>(val origin: String, val proxy: T, var sampleOrder: Long? = null)
    private val entries = mutableListOf<Entry<T>>()
    private var sampleOrder = 0L
    val size: Int get() = entries.size

    fun registerReady(origin: String, proxy: T): Boolean {
        entries.firstOrNull { it.proxy === proxy }?.let { return it.origin == origin }
        val sameOrigin = entries.filter { it.origin == origin }
        if (sameOrigin.size >= maxPerOrigin) evict(sameOrigin)
        if (entries.size >= maxProxies) evict(entries)
        entries.add(Entry(origin, proxy))
        return true
    }

    fun contains(origin: String, proxy: T): Boolean =
        entries.any { it.origin == origin && it.proxy === proxy }

    fun recordSample(origin: String, proxy: T): Boolean {
        val entry = entries.firstOrNull { it.origin == origin && it.proxy === proxy } ?: return false
        entry.sampleOrder = ++sampleOrder
        return true
    }

    fun remove(origin: String, proxy: T) {
        entries.removeAll { it.origin == origin && it.proxy === proxy }
    }

    fun broadcast(send: (T) -> Unit) {
        for (entry in entries.toList()) {
            if (entries.none { it === entry }) continue
            try {
                send(entry.proxy)
            } catch (_: RuntimeException) {
                entries.remove(entry)
            }
        }
    }

    fun clear() {
        entries.clear()
        sampleOrder = 0L
    }

    private fun evict(candidates: List<Entry<T>>) {
        // Repeated ready-only documents must not crowd out a game sending real samples.
        // When every entry has sampled, retire the least recently observed document.
        val victim = candidates.firstOrNull { it.sampleOrder == null }
            ?: candidates.minBy { checkNotNull(it.sampleOrder) }
        entries.remove(victim)
    }
}
