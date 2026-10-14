package app.yahagi.kancollebrowser.browser

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.FutureTask
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject

/**
 * Fetches gadget client files from a mirror endpoint with a disk cache and a
 * WebView fallback. Every attempt has a shared total deadline.
 *
 * The engine is Android-free so it can be exercised by plain JVM unit tests.
 */
class GadgetBypassEngine(
    private val cache: GadgetBypassCache,
    private val connectTimeoutMs: Int = 8_000,
    private val readTimeoutMs: Int = 15_000,
    private val maxResponseBytes: Int = 64 * 1024 * 1024,
    private val endpointValidator: (String) -> Boolean = {
        GadgetBypassRules.validateEndpoint(it).isValid
    },
    private val onCacheHit: (String) -> Unit = {},
    private val totalTimeoutMs: Long = 5_000,
    private val failureCooldownMs: Long = 15_000,
    private val nanoTime: () -> Long = System::nanoTime,
) {
    private data class Flight(val deadline: Long, val task: FutureTask<ByteArray?>)
    private val inFlight = ConcurrentHashMap<String, Flight>()
    private val failures = ConcurrentHashMap<String, Long>()

    /**
     * Returns the bytes that should be served for [originalUrl], or null when the
     * request is out of scope or every source failed.
     */
    fun fetch(originalUrl: String, endpoint: String): ByteArray? {
        if (!GadgetBypassRules.shouldIntercept(originalUrl, "GET")) return null
        if (!endpointValidator(endpoint)) return null

        val cacheKey = "${endpoint.trimEnd('/')}\n$originalUrl"
        cache.get(cacheKey)?.let {
            if (validBody(originalUrl, it)) {
                onCacheHit(originalUrl)
                return it
            }
            cache.remove(cacheKey)
        }

        val rewritten = GadgetBypassRules.rewrite(originalUrl, endpoint) ?: return null
        val now = nanoTime()
        val failedAt = failures[cacheKey]
        if (failedAt != null && now - failedAt < TimeUnit.MILLISECONDS.toNanos(failureCooldownMs)) return null
        val deadline = now + TimeUnit.MILLISECONDS.toNanos(totalTimeoutMs.coerceAtLeast(1))
        val cacheGeneration = cache.generation()
        val created = Flight(deadline, FutureTask {
            runCatching {
                download(rewritten, originalUrl, deadline)?.also { body ->
                    if (remainingMs(deadline) > 0) cache.put(cacheKey, body, cacheGeneration)
                }
            }.getOrNull()
        })
        val shared = inFlight.putIfAbsent(cacheKey, created) ?: created
        if (shared === created) {
            try {
                downloads.execute(created.task)
            } catch (_: Exception) {
                created.task.cancel(false)
            }
        }
        val bytes = runCatching {
            val remaining = remainingMs(shared.deadline)
            if (remaining <= 0) null else shared.task.get(remaining, TimeUnit.MILLISECONDS)
        }.getOrNull()
        if (bytes == null) {
            shared.task.cancel(true)
            // Bound negative-cache metadata even if a broken page keeps changing URLs.
            if (failures.size >= 256) failures.entries.removeIf {
                nanoTime() - it.value >= TimeUnit.MILLISECONDS.toNanos(failureCooldownMs)
            }
            if (failures.size < 256) failures[cacheKey] = nanoTime()
        } else failures.remove(cacheKey)
        if (shared.task.isDone) inFlight.remove(cacheKey, shared)
        return bytes
    }

    private fun remainingMs(deadline: Long): Long =
        TimeUnit.NANOSECONDS.toMillis(deadline - nanoTime()).coerceAtLeast(0)

    private fun download(urlString: String, originalUrl: String, deadline: Long): ByteArray? {
        val connection = URL(urlString).openConnection() as HttpURLConnection
        connection.requestMethod = "GET"
        val remaining = remainingMs(deadline).takeIf { it > 0 } ?: return null
        connection.connectTimeout = minOf(connectTimeoutMs.toLong(), remaining).coerceAtLeast(1).toInt()
        connection.readTimeout = minOf(readTimeoutMs.toLong(), remaining).coerceAtLeast(1).toInt()
        connection.instanceFollowRedirects = false
        connection.setRequestProperty("User-Agent", "Yahagi-GadgetBypass/1.0")
        try {
            val code = connection.responseCode
            if (code != HttpURLConnection.HTTP_OK || connection.getHeaderField("Set-Cookie") != null ||
                connection.getHeaderField("Set-Cookie2") != null ||
                !validMime(originalUrl, connection.contentType)
            ) return null
            val length = connection.contentLengthLong
            if (length == 0L || length > maxResponseBytes) return null
            val bytes = connection.inputStream.use { readLimited(it, connection, deadline) } ?: return null
            if (length >= 0 && length != bytes.size.toLong() || remainingMs(deadline) <= 0 ||
                !validBody(originalUrl, bytes)
            ) return null
            return bytes
        } finally {
            connection.disconnect()
        }
    }

    private fun readLimited(input: InputStream, connection: HttpURLConnection, deadline: Long): ByteArray? {
        val buffer = ByteArrayOutputStream()
        val chunk = ByteArray(8192)
        var total = 0
        while (true) {
            val remaining = remainingMs(deadline).takeIf { it > 0 } ?: return null
            connection.readTimeout = minOf(readTimeoutMs.toLong(), remaining).coerceAtLeast(1).toInt()
            val read = input.read(chunk)
            if (read < 0) break
            total += read
            if (total > maxResponseBytes) return null
            buffer.write(chunk, 0, read)
        }
        return buffer.toByteArray()
    }

    private fun validMime(url: String, header: String?): Boolean {
        val actual = header?.substringBefore(';')?.trim()?.lowercase().orEmpty()
        val expected = GadgetBypassRules.mimeTypeFor(url).mime
        if (actual.isEmpty() || actual == "application/octet-stream") return true
        if (actual == expected) return true
        return when (expected) {
            "application/javascript" -> actual in setOf("text/javascript", "application/x-javascript", "text/ecmascript", "application/ecmascript", "text/plain")
            "text/css", "application/json", "image/svg+xml" -> actual == "text/plain"
            "font/woff" -> actual == "application/font-woff"
            "font/woff2" -> actual == "application/font-woff2"
            else -> false
        }
    }

    private fun validBody(url: String, bytes: ByteArray): Boolean {
        if (bytes.isEmpty() || bytes.size > maxResponseBytes) return false
        val expected = GadgetBypassRules.mimeTypeFor(url).mime
        val prefix = bytes.take(512).toByteArray().toString(Charsets.UTF_8).trimStart('\uFEFF', ' ', '\t', '\r', '\n')
        val markupPrefix = prefix.replaceFirst(Regex("(?s)^(?:<!--.*?-->\\s*)+"), "")
        if (expected != "text/html" && Regex("(?is)^<(?:!doctype\\s+html|html\\b|head\\b|body\\b)").containsMatchIn(markupPrefix)) return false
        fun begins(vararg values: Int): Boolean = bytes.size >= values.size &&
            values.indices.all { bytes[it].toInt() and 255 == values[it] }
        return when (expected) {
            "image/png" -> begins(137, 80, 78, 71, 13, 10, 26, 10)
            "image/jpeg" -> begins(255, 216, 255)
            "image/gif" -> prefix.startsWith("GIF87a") || prefix.startsWith("GIF89a")
            "image/webp" -> prefix.startsWith("RIFF") && bytes.size >= 12 && bytes.copyOfRange(8, 12).toString(Charsets.US_ASCII) == "WEBP"
            "font/woff" -> prefix.startsWith("wOFF")
            "font/woff2" -> prefix.startsWith("wOF2")
            "font/ttf" -> begins(0, 1, 0, 0) || prefix.startsWith("true") || prefix.startsWith("OTTO")
            "application/wasm" -> begins(0, 97, 115, 109)
            "audio/ogg" -> prefix.startsWith("OggS")
            "audio/mpeg" -> prefix.startsWith("ID3") || bytes.size >= 2 && begins(255) && bytes[1].toInt() and 224 == 224
            "video/mp4" -> bytes.size >= 8 && bytes.copyOfRange(4, 8).toString(Charsets.US_ASCII) == "ftyp"
            "image/svg+xml" -> Regex("(?is)<svg\\b").containsMatchIn(prefix)
            "application/json" -> runCatching {
                val text = bytes.toString(Charsets.UTF_8).trimStart('\uFEFF', ' ', '\t', '\r', '\n')
                if (text.startsWith("[")) JSONArray(text) else JSONObject(text)
            }.isSuccess
            "application/javascript", "text/css" -> !prefix.startsWith("<?xml", ignoreCase = true)
            else -> true
        }
    }

    private companion object {
        // A stalled DNS/socket cannot grow an unbounded pool or block fallback callers.
        val downloads = ThreadPoolExecutor(2, 2, 30, TimeUnit.SECONDS,
            ArrayBlockingQueue(8), { task -> Thread(task, "gadget-mirror-download").apply { isDaemon = true } },
            ThreadPoolExecutor.AbortPolicy())
    }
}
