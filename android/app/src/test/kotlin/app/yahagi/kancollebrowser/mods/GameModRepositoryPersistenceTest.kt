package app.yahagi.kancollebrowser.mods

import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class GameModRepositoryPersistenceTest {
    @get:Rule val temporary = TemporaryFolder()
    private val path = "kcs2/resources/ship/full/0001_abcd.png"
    private val url = "https://w01x.kancolle-server.com/$path"

    @Test fun `beta3 index restores resources and independent draft without rewriting on read`() {
        val root = temporary.newFolder()
        val repository = GameModRepository(root)
        val preview = repository.preflight(archive().inputStream(), "test.zip")
        repository.commitImport(preview["token"] as String)
        val pack = (repository.status()["packages"] as List<*>).single() as Map<*, *>
        val resource = (pack["resources"] as List<*>).single() as Map<*, *>
        val config = mapOf("master" to true, "order" to listOf(pack["id"]),
            "enabledPackages" to listOf(pack["id"]), "enabledResources" to listOf(resource["id"]))
        repository.saveDraft(config)
        repository.finishApply(repository.applyDraft())
        repository.saveDraft(config + ("master" to false))
        val index = root.resolve("state.json")
        val canonical = JsonParser.parseString(index.readText()).asJsonObject
        val legacy = beta3(canonical)
        index.writeText(legacy.toString())
        val original = index.readBytes()

        val restored = GameModRepository(root)
        assertEquals(false, (restored.status()["draft"] as Map<*, *>)["master"])
        assertEquals(true, (restored.status()["applied"] as Map<*, *>)["master"])
        assertEquals(true, restored.status()["pending"])
        assertArrayEquals(png(), restored.openResource(url, "GET", emptyMap())!!.inputStream.use { it.readBytes() })
        assertArrayEquals(original, index.readBytes())

        restored.saveDraft(restored.status()["draft"] as Map<*, *>)
        val rewritten = JsonParser.parseString(index.readText()).asJsonObject
        assertEquals(canonical, rewritten)
        assertEquals(restored.status()["draft"], GameModRepository(root).status()["draft"])
    }

    @Test fun `ambiguous beta3 index fails before deleting any existing package`() {
        val root = temporary.newFolder()
        val sentinel = root.resolve("packages/preserve/resource.png").apply { parentFile.mkdirs(); writeBytes(png()) }
        val staging = root.resolve("staging/recover/resource.png").apply { parentFile.mkdirs(); writeBytes(png()) }
        val pending = root.resolve("state-recover.tmp").apply { writeText("keep") }
        val index = root.resolve("state.json").apply {
            writeText("""{"version":1,"a":1,"b":[],"c":{"a":false,"b":[],"c":[],"d":[]},"d":{"a":false,"b":[],"c":[],"d":[]},"e":0,"f":[]}""")
        }
        val original = index.readBytes()
        val failure = runCatching { GameModRepository(root) }.exceptionOrNull()
        assertEquals("storage_error", (failure as? GameModException)?.code)
        assertArrayEquals(original, index.readBytes())
        assertArrayEquals(png(), sentinel.readBytes())
        assertArrayEquals(png(), staging.readBytes())
        assertEquals("keep", pending.readText())
    }

    @Test fun `beta3 pending removal keeps the applied package and permits cancellation`() {
        val root = temporary.newFolder()
        val repository = GameModRepository(root)
        val preview = repository.preflight(archive().inputStream(), "test.zip")
        repository.commitImport(preview["token"] as String)
        val pack = (repository.status()["packages"] as List<*>).single() as Map<*, *>
        val resource = (pack["resources"] as List<*>).single() as Map<*, *>
        repository.saveDraft(mapOf("master" to true, "order" to listOf(pack["id"]),
            "enabledPackages" to listOf(pack["id"]), "enabledResources" to listOf(resource["id"])))
        repository.finishApply(repository.applyDraft())
        repository.removePackage(pack["id"] as String)
        val index = root.resolve("state.json")
        index.writeText(beta3(JsonParser.parseString(index.readText()).asJsonObject).toString())

        val restored = GameModRepository(root)
        assertEquals(true, ((restored.status()["packages"] as List<*>).single() as Map<*, *>)["pendingRemoval"])
        assertArrayEquals(png(), restored.openResource(url, "GET", emptyMap())!!.inputStream.use { it.readBytes() })
        restored.cancelChanges()
        assertEquals(false, ((restored.status()["packages"] as List<*>).single() as Map<*, *>)["pendingRemoval"])
        assertArrayEquals(png(), GameModRepository(root).openResource(url, "GET", emptyMap())!!.inputStream.use { it.readBytes() })
    }

    @Test fun `invalid beta3 paths remain rejected and preserve the original index`() {
        val root = temporary.newFolder()
        val index = root.resolve("state.json").apply {
            writeText("""{"a":1,"b":[{"a":"00000000-0000-0000-0000-000000000001","b":"test","c":1,"d":0,"e":[{"a":"00000000-0000-0000-0000-000000000001:0","b":"$path","c":"ship","d":"test","e":true,"h":"../outside.png","i":1,"j":["$path"],"l":{}}],"f":[],"g":false,"h":""}],"c":{"a":false,"b":[],"c":[],"d":[]},"d":{"a":false,"b":[],"c":[],"d":[]},"e":0,"f":[]}""")
        }
        val original = index.readBytes()
        assertEquals("storage_error", (runCatching { GameModRepository(root) }.exceptionOrNull() as? GameModException)?.code)
        assertArrayEquals(original, index.readBytes())
    }

    /** Frozen field names from the shipped beta3 R8 mapping, not a production codec. */
    private fun beta3(json: JsonObject): JsonObject {
        fun rename(source: JsonObject, names: List<String>) = JsonObject().apply {
            names.forEachIndexed { index, name -> source[name]?.let { add(('a' + index).toString(), it.deepCopy()) } }
        }
        val copy = json.deepCopy()
        for (name in listOf("packages", "appliedPackages")) {
            // Transform a temporary root so the original canonical fixture stays intact.
            val values = copy.getAsJsonArray(name)
            values.forEachIndexed { index, node ->
                val pack = node.asJsonObject
                val resources = pack.getAsJsonArray("resources")
                resources.forEachIndexed { r, resource -> resources.set(r, rename(resource.asJsonObject,
                    listOf("id", "path", "kind", "label", "supported", "reason", "groupId", "relativeFile", "sizeBytes", "sourcePaths", "coordinateShipId", "coordinateGraph"))) }
                values.set(index, rename(pack, listOf("id", "name", "sizeBytes", "importedAt", "resources", "warnings", "pendingRemoval", "sourceFingerprint")))
            }
        }
        for (name in listOf("draft", "applied")) copy.add(name,
            rename(copy.getAsJsonObject(name), listOf("master", "order", "enabledPackages", "enabledResources")))
        return rename(copy, listOf("version", "packages", "draft", "applied", "sessionId", "appliedPackages"))
    }

    private fun archive() = ByteArrayOutputStream().also { out -> ZipOutputStream(out).use {
        it.putNextEntry(ZipEntry("cache/$path")); it.write(png()); it.closeEntry()
    } }.toByteArray()

    private fun png() = ByteArrayOutputStream().also { out ->
        val data = DataOutputStream(out)
        data.write(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
        fun chunk(type: String, bytes: ByteArray) {
            val kind = type.toByteArray(Charsets.US_ASCII)
            data.writeInt(bytes.size); data.write(kind); data.write(bytes)
            data.writeInt(CRC32().apply { update(kind); update(bytes) }.value.toInt())
        }
        val header = ByteArrayOutputStream().also { DataOutputStream(it).apply { writeInt(1); writeInt(1); write(byteArrayOf(8, 6, 0, 0, 0)) } }.toByteArray()
        val compressed = ByteArrayOutputStream().also { DeflaterOutputStream(it).use { it.write(byteArrayOf(0, 0, 0, 0, -1)) } }.toByteArray()
        chunk("IHDR", header); chunk("IDAT", compressed); chunk("IEND", byteArrayOf())
    }.toByteArray()
}
