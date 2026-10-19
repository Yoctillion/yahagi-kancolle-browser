package app.yahagi.kancollebrowser.mods

import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonNull
import com.google.gson.JsonObject
import com.google.gson.JsonPrimitive
import com.google.gson.stream.JsonReader
import com.google.gson.stream.JsonToken
import java.io.StringReader

internal data class GameModCoordinateData(val graph: Map<String, List<Int>>, val metadataIgnored: Boolean = false, val unknownFields: Boolean = false)

internal object GameModCoordinateParser {
    val fields = listOf("boko_n", "boko_d", "kaisyu_n", "kaisyu_d", "kaizo_n", "kaizo_d", "map_n", "map_d",
        "ensyuf_n", "ensyuf_d", "ensyue_n", "ensyue_d", "battle_n", "battle_d", "weda", "wedb", "wedc", "wedd")
    fun parse(bytes: ByteArray, format: String): GameModCoordinateData {
        if (bytes.size > 131072) invalid()
        try {
            val text = bytes.toString(Charsets.UTF_8).removePrefix("\uFEFF")
            val parsed = when (format.lowercase()) { "ini" -> ini(text); "json" -> json(text); else -> invalid() }
            if (parsed.graph.isEmpty()) invalid()
            return parsed
        } catch (error: Exception) {
            if (error is GameModException) throw error
            invalid()
        }
    }
    fun merge(parts: List<GameModCoordinateData>): GameModCoordinateData {
        val graph = linkedMapOf<String, List<Int>>()
        parts.forEach { part -> part.graph.forEach { (key, value) ->
            if (key in graph && graph[key] != value) conflict()
            graph[key] = value.toList()
        } }
        if (graph.isEmpty()) invalid()
        return GameModCoordinateData(graph, parts.any { it.metadataIgnored }, parts.any { it.unknownFields })
    }
    private fun ini(text: String): GameModCoordinateData {
        val graph = linkedMapOf<String, String>()
        var section = ""; var metadata = false; var unknown = false
        text.lineSequence().forEach { raw ->
            val line = raw.trim()
            if (line.isEmpty() || line.startsWith(';') || line.startsWith('#')) return@forEach
            if (line.startsWith('[') && line.endsWith(']')) { section = line.substring(1, line.length - 1).lowercase(); return@forEach }
            val split = line.indexOf('='); if (split < 1) invalid()
            val name = line.substring(0, split).trim(); val value = line.substring(split + 1).trim()
            when (section) {
                "info" -> if (value.isNotEmpty() && value != "false") metadata = true
                "graph" -> {
                    if (name !in fields.flatMap { listOf("${it}_left", "${it}_top") }) unknown = true
                    else {
                        if (name in graph && graph[name] != value) conflict()
                        graph[name] = value
                    }
                }
                else -> unknown = true
            }
        }
        val output = linkedMapOf<String, List<Int>>()
        fields.forEach { key ->
            val left = graph["${key}_left"]; val top = graph["${key}_top"]
            if (left != null || top != null) {
                if (left == null || top == null) invalid()
                if (left.isNotEmpty() || top.isNotEmpty()) output["api_$key"] = listOf(integer(left), integer(top))
            }
        }
        return GameModCoordinateData(output, metadata, unknown)
    }
    private fun json(text: String): GameModCoordinateData {
        val root = readJson(text).takeIf { it.isJsonObject }?.asJsonObject ?: invalid()
        val input = root["api_mst_shipgraph"]?.takeIf { it.isJsonObject }?.asJsonObject ?: invalid()
        val output = linkedMapOf<String, List<Int>>()
        var unknown = false
        input.entrySet().forEach { (key, value) ->
            if (key.removePrefix("api_") !in fields || !key.startsWith("api_")) unknown = true
            else {
                if (!value.isJsonArray || value.asJsonArray.size() != 2) invalid()
                output[key] = value.asJsonArray.map { item ->
                    if (!item.isJsonPrimitive || !item.asJsonPrimitive.isNumber) invalid()
                    integer(item.asString)
                }
            }
        }
        val metadata = root["api_mst_ship"]?.let { info ->
            if (!info.isJsonObject) invalid()
            info.asJsonObject.entrySet().any { (_, value) ->
                !(value.isJsonNull || value == JsonPrimitive(false) || value == JsonPrimitive(""))
            }
        } ?: false
        return GameModCoordinateData(output, metadata, unknown)
    }
    private fun readJson(text: String): JsonElement {
        var nodes = 0
        JsonReader(StringReader(text)).use { reader ->
            fun read(depth: Int): JsonElement {
                if (depth > 8 || ++nodes > 256) invalid()
                return when (reader.peek()) {
                    JsonToken.BEGIN_OBJECT -> JsonObject().apply {
                        reader.beginObject()
                        while (reader.hasNext()) {
                            val key = reader.nextName(); val value = read(depth + 1)
                            if (has(key) && get(key) != value) conflict()
                            add(key, value)
                        }
                        reader.endObject()
                    }
                    JsonToken.BEGIN_ARRAY -> JsonArray().apply {
                        reader.beginArray(); while (reader.hasNext()) add(read(depth + 1)); reader.endArray()
                    }
                    JsonToken.STRING -> JsonPrimitive(reader.nextString())
                    JsonToken.NUMBER -> JsonPrimitive(reader.nextString().toBigDecimal())
                    JsonToken.BOOLEAN -> JsonPrimitive(reader.nextBoolean())
                    JsonToken.NULL -> { reader.nextNull(); JsonNull.INSTANCE }
                    else -> invalid()
                }
            }
            val result = read(0)
            if (reader.peek() != JsonToken.END_DOCUMENT) invalid()
            return result
        }
    }
    private fun integer(value: String): Int = if (Regex("-?(0|[1-9][0-9]*)").matches(value)) value.toIntOrNull() ?: invalid() else invalid()
    private fun invalid(): Nothing = throw GameModException("invalid_coordinates", "Coordinate metadata contains invalid or unsupported values")
    private fun conflict(): Nothing = throw GameModException("coordinate_conflict", "Coordinate formats disagree for the same field")
}
