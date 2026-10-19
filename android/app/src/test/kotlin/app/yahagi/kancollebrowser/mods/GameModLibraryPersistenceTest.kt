package app.yahagi.kancollebrowser.mods

import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream

class GameModLibraryPersistenceTest {
    @get:Rule val temporary = TemporaryFolder()
    private val id = "11111111-1111-4111-8111-111111111111"
    private val deletedId = "22222222-2222-4222-8222-222222222222"
    private val resource = "kcs2/resources/ship/full/0001_1234_secret.png"
    private val hash = "a".repeat(64)

    @Test fun `canonical library with cleaned tombstones opens without modifying source files`() {
        val root = temporary.newFolder()
        val bytes = writeEnvelope(root, "library.json", canonicalState(), 17)
        val library = open(root)
        assertEquals(listOf("canonical"), library.appliedConfiguration()!!["order"])
        assertEquals(emptyList<String>(), library.status()["deletionFailures"])
        assertEquals(bytes, root.resolve("library.json").readText())
        assertEquals(setOf("library.json"), root.list()!!.toSet())
    }

    @Test fun `beta3 obfuscated state restores nested package tombstone and applied configuration`() {
        val root = temporary.newFolder()
        val payload = legacyState().apply { getAsJsonArray("a").add(legacyRecord()) }
        val bytes = writeEnvelope(root, "library.json", payload, 18)
        val library = open(root)
        assertEquals(listOf("legacy"), library.appliedConfiguration()!!["order"])
        val record = (library.status()["packages"] as List<*>).single() as Map<*, *>
        assertEquals(id, record["id"])
        assertEquals("Ship", record["name"])
        assertEquals("Ship", record["path"])
        assertEquals(hash, record["contentHash"])
        assertEquals("cache.zip", record["sourceZip"])
        assertEquals(hash, record["sourceHash"])
        assertEquals("keep literal key", library.appliedConfiguration()!!["a"])
        assertEquals(emptyList<String>(), library.status()["deletionFailures"])
        assertEquals(bytes, root.resolve("library.json").readText())
    }

    @Test fun `highest valid generation wins across canonical and beta3 formats`() {
        val root = temporary.newFolder()
        writeEnvelope(root, "library.json", canonicalState(), 17)
        writeEnvelope(root, ".yahagi-library-backup.json", legacyState(), 18)
        assertEquals(listOf("legacy"), open(root).appliedConfiguration()!!["order"])
    }

    @Test fun `newer canonical state also supersedes an older beta3 backup`() {
        val root = temporary.newFolder()
        writeEnvelope(root, "library.json", canonicalState(), 21)
        writeEnvelope(root, ".yahagi-library-backup.json", legacyState(), 20)
        assertEquals(listOf("canonical"), open(root).appliedConfiguration()!!["order"])
    }

    @Test fun `invalid original beta3 checksum falls back without rewriting either index`() {
        val root = temporary.newFolder()
        val older = writeEnvelope(root, "library.json", canonicalState(), 17)
        val envelope = JsonParser.parseString(envelope(legacyState(), 18)).asJsonObject
        envelope.getAsJsonObject("state").getAsJsonObject("b").addProperty("modified", true)
        val damaged = envelope.toString()
        root.resolve(".yahagi-library-backup.json").writeText(damaged)
        assertEquals(listOf("canonical"), open(root).appliedConfiguration()!!["order"])
        assertEquals(older, root.resolve("library.json").readText())
        assertEquals(damaged, root.resolve(".yahagi-library-backup.json").readText())
    }

    @Test fun `beta3 marker is scanned with its original identity and rewritten using stable keys`() {
        val root = temporary.newFolder()
        val directory = root.resolve("Ship").apply { mkdirs() }
        directory.resolve(resource).apply { parentFile!!.mkdirs(); writeBytes(png()) }
        val contentHash = open(root).fingerprintLocalTree(directory)
        val marker = legacyRecord().apply { addProperty("d", contentHash) }
        val original = marker.toString()
        directory.resolve(".yahagi-package.json").writeText(original)
        val library = open(root)
        val scan = library.scan()
        assertEquals(id, scan.items.single()["id"])
        assertEquals("unchanged", scan.items.single()["status"])
        assertEquals(original, directory.resolve(".yahagi-package.json").readText())
        assertEquals(id, library.acceptScan(scan.token).single().id)
        val savedMarker = JsonParser.parseString(directory.resolve(".yahagi-package.json").readText()).asJsonObject
        assertEquals(id, savedMarker["id"].asString)
        assertEquals(contentHash, savedMarker["contentHash"].asString)
        assertEquals(1, savedMarker["schemaVersion"].asInt)
        assertEquals("cache.zip", savedMarker["sourceZip"].asString)
        assertEquals(hash, savedMarker["sourceHash"].asString)
        assertTrue(savedMarker["sourceConsumed"].asBoolean)
        assertFalse(savedMarker.has("a"))
        val saved = root.listFiles()!!.filter { it.name in setOf("library.json", ".yahagi-library-backup.json") }
            .map { JsonParser.parseString(it.readText()).asJsonObject }.maxBy { it["generation"].asLong }
        val state = saved.getAsJsonObject("state")
        assertEquals(1, state["schemaVersion"].asInt)
        assertTrue(state["packages"].isJsonArray)
        assertTrue(state["tombstones"].isJsonArray)
        assertFalse(state.has("a"))
        assertEquals(id, ((open(root).status()["packages"] as List<*>).single() as Map<*, *>)["id"])
    }

    @Test fun `saving recovered beta3 state writes canonical nested records and tombstones`() {
        val root = temporary.newFolder()
        writeEnvelope(root, "library.json", legacyState().apply { getAsJsonArray("a").add(legacyRecord()) }, 18)
        open(root).saveAppliedConfiguration(mapOf("schemaVersion" to 1, "order" to listOf(id)))
        val payload = JsonParser.parseString(root.resolve("library.json").readText()).asJsonObject.getAsJsonObject("state")
        assertEquals(id, payload.getAsJsonArray("packages")[0].asJsonObject["id"].asString)
        assertEquals("cache.zip", payload.getAsJsonArray("packages")[0].asJsonObject["sourceZip"].asString)
        assertEquals(hash, payload.getAsJsonArray("packages")[0].asJsonObject["sourceHash"].asString)
        assertTrue(payload.getAsJsonArray("packages")[0].asJsonObject["sourceConsumed"].asBoolean)
        assertEquals(deletedId, payload.getAsJsonArray("tombstones")[0].asJsonObject["id"].asString)
        assertEquals("deleted.zip", payload.getAsJsonArray("tombstones")[0].asJsonObject["sourceZip"].asString)
        assertEquals(hash, payload.getAsJsonArray("tombstones")[0].asJsonObject["sourceHash"].asString)
        assertTrue(payload.getAsJsonArray("tombstones")[0].asJsonObject["cleaned"].asBoolean)
        assertFalse(payload.getAsJsonArray("packages")[0].asJsonObject.has("a"))
        assertEquals(listOf(id), open(root).appliedConfiguration()!!["order"])
    }

    @Test fun `mixed top level canonical and obfuscated fields are rejected without changing files`() {
        rejected(canonicalState().apply { add("a", JsonArray()) })
        rejected(legacyState().apply { add("packages", JsonArray()) })
    }

    @Test fun `mixed package fields are rejected even when alias values agree`() {
        rejected(canonicalState().apply { getAsJsonArray("packages").add(canonicalRecord().apply { addProperty("a", id) }) })
        rejected(legacyState().apply { getAsJsonArray("a").add(legacyRecord().apply { addProperty("id", id) }) })
    }

    @Test fun `mixed tombstone fields are rejected even when alias values agree`() {
        rejected(canonicalState().apply { getAsJsonArray("tombstones")[0].asJsonObject.addProperty("a", deletedId) })
        rejected(legacyState().apply { getAsJsonArray("c")[0].asJsonObject.addProperty("id", deletedId) })
    }

    @Test fun `unsupported versions invalid identities paths and hashes remain rejected`() {
        rejected(canonicalState().apply { addProperty("schemaVersion", 2) })
        for ((key, value) in listOf("a" to "invalid-id", "c" to "../escape", "d" to "bad-hash")) {
            rejected(legacyState().apply { getAsJsonArray("a").add(legacyRecord().apply { addProperty(key, value) }) })
        }
        rejected(legacyState().apply { getAsJsonArray("a").add(legacyRecord().apply { addProperty("g", 2) }) })
    }

    @Test fun `mixed marker fields are invalid rather than silently acquiring a new identity`() {
        val root = temporary.newFolder()
        val directory = root.resolve("Ship").apply { mkdirs() }
        directory.resolve(resource).apply { parentFile!!.mkdirs(); writeBytes(png()) }
        val marker = canonicalRecord().apply { addProperty("a", id) }.toString()
        directory.resolve(".yahagi-package.json").writeText(marker)
        val scan = open(root).scan()
        assertEquals("invalid", scan.items.single()["status"])
        assertEquals(marker, directory.resolve(".yahagi-package.json").readText())
    }

    @Test fun `marker without schema version remains invalid for canonical and beta3 fields`() {
        for (marker in listOf(canonicalRecord().apply { remove("schemaVersion") }, legacyRecord().apply { remove("g") })) {
            val root = temporary.newFolder()
            val directory = root.resolve("Ship").apply { mkdirs() }
            directory.resolve(resource).apply { parentFile!!.mkdirs(); writeBytes(png()) }
            val original = marker.toString()
            directory.resolve(".yahagi-package.json").writeText(original)
            assertEquals("invalid", open(root).scan().items.single()["status"])
            assertEquals(original, directory.resolve(".yahagi-package.json").readText())
        }
    }

    private fun open(root: File) = GameModLibrary(GameModFileLibraryStore(root), temporary.newFolder())
    private fun rejected(payload: JsonObject) {
        val root = temporary.newFolder()
        val bytes = writeEnvelope(root, "library.json", payload, 1)
        try { open(root); fail("Invalid metadata accepted: $payload") }
        catch (error: GameModException) { assertEquals("library_metadata_invalid", error.code) }
        assertEquals(bytes, root.resolve("library.json").readText())
        assertEquals(setOf("library.json"), root.list()!!.toSet())
    }
    private fun canonicalState() = JsonObject().apply {
        addProperty("schemaVersion", 1)
        add("packages", JsonArray())
        add("applied", JsonObject().apply { add("order", JsonArray().apply { add("canonical") }) })
        add("tombstones", JsonArray().apply { add(JsonObject().apply {
            addProperty("id", deletedId); addProperty("path", "Deleted"); addProperty("cleaned", true)
        }) })
    }
    private fun legacyState() = JsonObject().apply {
        add("a", JsonArray())
        add("b", JsonObject().apply {
            add("order", JsonArray().apply { add("legacy") }); addProperty("a", "keep literal key")
        })
        add("c", JsonArray().apply { add(JsonObject().apply {
            addProperty("a", deletedId); addProperty("b", "Deleted")
            addProperty("c", "deleted.zip"); addProperty("d", hash); addProperty("e", true)
        }) })
    }
    private fun canonicalRecord() = JsonObject().apply {
        addProperty("id", id); addProperty("name", "Ship"); addProperty("path", "Ship")
        addProperty("contentHash", hash); addProperty("schemaVersion", 1); addProperty("sourceConsumed", false)
    }
    private fun legacyRecord() = JsonObject().apply {
        addProperty("a", id); addProperty("b", "Ship"); addProperty("c", "Ship")
        addProperty("d", hash); addProperty("e", "cache.zip"); addProperty("f", hash)
        addProperty("g", 1); addProperty("h", true)
    }
    private fun writeEnvelope(root: File, name: String, payload: JsonObject, generation: Long): String =
        envelope(payload, generation).also { root.resolve(name).writeText(it) }
    private fun envelope(payload: JsonObject, generation: Long) = JsonObject().apply {
        addProperty("schemaVersion", 1); addProperty("generation", generation)
        addProperty("sha256", MessageDigest.getInstance("SHA-256").digest(payload.toString().toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 255) })
        add("state", payload)
    }.toString()
    private fun png(): ByteArray {
        val output = ByteArrayOutputStream(); val writer = DataOutputStream(output)
        writer.write(byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
        fun chunk(type: String, bytes: ByteArray) {
            val tag = type.toByteArray(); writer.writeInt(bytes.size); writer.write(tag); writer.write(bytes)
            writer.writeInt(CRC32().also { it.update(tag); it.update(bytes) }.value.toInt())
        }
        chunk("IHDR", ByteArrayOutputStream().also { DataOutputStream(it).apply { writeInt(1); writeInt(1); write(byteArrayOf(8, 6, 0, 0, 0)) } }.toByteArray())
        chunk("IDAT", ByteArrayOutputStream().also { DeflaterOutputStream(it).use { it.write(byteArrayOf(0, 0, 0, 0, 0xff.toByte())) } }.toByteArray())
        chunk("IEND", byteArrayOf()); return output.toByteArray()
    }
}
