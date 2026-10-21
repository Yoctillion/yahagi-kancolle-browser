package app.yahagi.kancollebrowser.mods

import com.google.gson.JsonElement
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.TimeUnit
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class GameModArchiveAuditRegressionTest {
    @get:Rule val temporaryFolder = TemporaryFolder()
    private val shipPath = "kcs2/resources/ship/full/0001_1234_secret.png"
    private val ini = "[graph]\nboko_n_left=3\nboko_n_top=4"
    private val json = """{"api_mst_shipgraph":{"api_boko_n":[3,4]}}"""

    @Test fun `oversized coordinate ZIP fails normally with a smaller heap than the entry`() {
        val source = temporaryFolder.newFile("oversized-coordinate.zip")
        writeLargeStoredCoordinateArchive(source, 64L * 1024 * 1024)
        val destination = temporaryFolder.newFolder("unpacked")
        runLowHeap("archive", source, destination)
        assertTrue("Rejected import must remove extracted files", destination.walkTopDown().none { it.isFile })
    }

    @Test fun `coordinate file growing after the size check still uses bounded memory`() {
        val source = temporaryFolder.newFile("growing-coordinate.json").apply { writeText(json) }
        runLowHeap("growing-file", source, temporaryFolder.root)
        assertEquals(64L * 1024 * 1024, source.length())
    }

    @Test fun `coordinate format suffixes bind regardless of suffix case`() {
        listOf(".config.ini", ".CONFIG.INI", ".config.INI", ".CONFIG.ini",
            ".config.json", ".CONFIG.JSON", ".config.JSON", ".CONFIG.json").forEach { suffix ->
            val sourcePath = "kcs/resources/swf/ships/secret$suffix"
            val text = if (suffix.endsWith("ini", ignoreCase = true)) ini else json
            val result = unpack(shipPath to png(), sourcePath to text.toByteArray())
            assertTrue("Image disabled by $suffix", result.resources.single { it.kind == "ship" }.supported)
            val coordinate = result.resources.single { it.kind == "coordinates" }
            assertTrue("Coordinates unmatched for $suffix", coordinate.supported)
            assertEquals("coordinates/ship/1", coordinate.path)
            assertEquals(mapOf("api_boko_n" to listOf(3, 4)), coordinate.coordinateGraph)
            assertEquals(listOf(sourcePath), coordinate.sourcePaths)
            assertFalse(result.warnings.contains("coordinate_dependency_unresolved"))
        }
    }

    @Test fun `mixed suffix cases merge equivalent coordinate formats once`() {
        val result = unpack(shipPath to png(),
            "kcs/resources/swf/ships/secret.CONFIG.INI" to ini.toByteArray(),
            "kcs/resources/swf/ships/secret.config.JSON" to json.toByteArray())
        assertTrue(result.resources.all { it.supported })
        val coordinate = result.resources.single { it.kind == "coordinates" }
        assertEquals(2, coordinate.sourcePaths.size)
        assertEquals(mapOf("api_boko_n" to listOf(3, 4)), coordinate.coordinateGraph)
    }

    @Test fun `coordinate resource stems remain case sensitive`() {
        val result = unpack(shipPath to png(), "kcs/resources/swf/ships/Secret.CONFIG.INI" to ini.toByteArray())
        assertEquals("coordinate_unmatched", result.resources.single { it.kind == "coordinates" }.reason)
        assertEquals("coordinate_dependency_unresolved", result.resources.single { it.kind == "ship" }.reason)
    }

    @Test fun `matching capitalized stems keep their case and bind separately`() {
        val result = unpack(shipPath to png(),
            "kcs2/resources/ship/full/0002_1234_Secret.png" to png(),
            "kcs/resources/swf/ships/secret.CONFIG.INI" to ini.toByteArray(),
            "kcs/resources/swf/ships/Secret.CONFIG.INI" to ini.replace("left=3", "left=5").toByteArray())
        assertTrue(result.resources.all { it.supported })
        assertEquals(mapOf("1" to listOf(3, 4), "2" to listOf(5, 4)),
            result.resources.filter { it.kind == "coordinates" }.associate { it.coordinateShipId to it.coordinateGraph["api_boko_n"] })
    }

    @Test fun `bare config filenames stay unbound in every format case`() {
        listOf("config.ini", "CONFIG.INI", "Config.JSON").forEach { filename ->
            val image = shipPath.replace("_secret.png", "_${filename.substringBefore('.')}.png")
            val text = if (filename.endsWith("ini", ignoreCase = true)) ini else json
            val result = unpack(image to png(), "kcs/resources/swf/ships/$filename" to text.toByteArray())
            assertEquals(filename, "coordinate_unmatched", result.resources.single { it.kind == "coordinates" }.reason)
            assertEquals("coordinate_dependency_unresolved", result.resources.single { it.kind == "ship" }.reason)
        }
    }

    @Test fun `unknown coordinate format is still unsupported`() {
        val result = unpack(shipPath to png(), "kcs/resources/swf/ships/secret.config.txt" to ini.toByteArray())
        assertTrue(result.resources.single { it.kind == "ship" }.supported)
        assertFalse(result.resources.single { it.path.endsWith(".txt") }.supported)
        assertTrue(result.resources.none { it.kind == "coordinates" })
    }

    @Test fun `exactly 128 KiB coordinate metadata remains accepted`() {
        val text = json.padEnd(128 * 1024, ' ')
        val result = unpack(shipPath to png(), "kcs/resources/swf/ships/secret.config.json" to text.toByteArray())
        assertTrue(result.resources.all { it.supported })
        assertEquals(mapOf("api_boko_n" to listOf(3, 4)), result.resources.single { it.kind == "coordinates" }.coordinateGraph)
    }

    @Test fun `one byte beyond coordinate limit preserves invalid coordinates error`() {
        val text = json.padEnd(128 * 1024 + 1, ' ')
        expect("invalid_coordinates") { unpack("kcs/resources/swf/ships/secret.config.json" to text.toByteArray()) }
    }

    @Test fun `invalid syntax and conflicting formats keep their original error codes`() {
        expect("invalid_coordinates") { unpack("kcs/resources/swf/ships/secret.config.json" to "not json".toByteArray()) }
        expect("coordinate_conflict") { unpack(shipPath to png(),
            "kcs/resources/swf/ships/secret.config.ini" to ini.toByteArray(),
            "kcs/resources/swf/ships/secret.config.json" to json.replace("[3,4]", "[3,5]").toByteArray()) }
    }

    private fun unpack(vararg files: Pair<String, ByteArray>): ArchiveResult {
        val bytes = ByteArrayOutputStream()
        ZipOutputStream(bytes).use { zip -> files.forEach { (name, data) ->
            val entry = ZipEntry(name).apply {
                method = ZipEntry.STORED; size = data.size.toLong(); compressedSize = size
                crc = CRC32().apply { update(data) }.value
            }
            zip.putNextEntry(entry); zip.write(data); zip.closeEntry()
        } }
        return GameModArchive().unpack(bytes.toByteArray().inputStream(), "regression.zip", temporaryFolder.newFolder())
    }

    private fun runLowHeap(mode: String, source: File, destination: File) {
        val locations = listOf(javaClass, GameModArchive::class.java, Unit::class.java, JsonElement::class.java, Test::class.java)
            .map { File(it.protectionDomain.codeSource.location.toURI()).path }
        val classpath = (System.getProperty("java.class.path").split(File.pathSeparator) + locations).distinct().joinToString(File.pathSeparator)
        val process = ProcessBuilder(File(System.getProperty("java.home"), "bin/java").path, "-Xmx48m", "-cp", classpath,
            javaClass.name, mode, source.path, destination.path).redirectErrorStream(true).start()
        if (!process.waitFor(60, TimeUnit.SECONDS)) {
            process.destroyForcibly()
            fail("Low heap coordinate validation timed out")
        }
        val output = process.inputStream.bufferedReader().use { it.readText() }
        assertEquals(output, 0, process.exitValue())
        assertTrue(output, output.contains("invalid_coordinates"))
    }

    private fun writeLargeStoredCoordinateArchive(file: File, size: Long) {
        val buffer = ByteArray(8192) { 32 }
        val crc = CRC32()
        repeat((size / buffer.size).toInt()) { crc.update(buffer) }
        ZipOutputStream(file.outputStream().buffered()).use { zip ->
            zip.putNextEntry(ZipEntry("kcs/resources/swf/ships/secret.config.json").apply {
                method = ZipEntry.STORED; this.size = size; compressedSize = size; this.crc = crc.value
            })
            repeat((size / buffer.size).toInt()) { zip.write(buffer) }
            zip.closeEntry()
        }
    }

    private fun png(): ByteArray {
        val output = ByteArrayOutputStream()
        val data = DataOutputStream(output)
        data.write(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
        fun chunk(type: String, bytes: ByteArray) {
            val kind = type.toByteArray(Charsets.US_ASCII)
            data.writeInt(bytes.size); data.write(kind); data.write(bytes)
            data.writeInt(CRC32().apply { update(kind); update(bytes) }.value.toInt())
        }
        val header = ByteArrayOutputStream().also { DataOutputStream(it).apply {
            writeInt(1); writeInt(1); write(byteArrayOf(8, 6, 0, 0, 0))
        } }.toByteArray()
        val compressed = ByteArrayOutputStream().also { DeflaterOutputStream(it).use { stream -> stream.write(byteArrayOf(0, 0, 0, 0, -1)) } }.toByteArray()
        chunk("IHDR", header); chunk("IDAT", compressed); chunk("IEND", byteArrayOf())
        return output.toByteArray()
    }

    private fun expect(code: String, block: () -> Unit) {
        try { block(); fail("Expected $code") } catch (error: GameModException) { assertEquals(code, error.code) }
    }

    companion object {
        @JvmStatic fun main(args: Array<String>) {
            val source = File(args[1])
            try {
                when (args[0]) {
                    "archive" -> source.inputStream().use { GameModArchive().unpack(it, source.name, File(args[2])) }
                    "growing-file" -> {
                        val growingFile = object : File(source.path) {
                            override fun length(): Long {
                                val observedLength = super.length()
                                RandomAccessFile(this, "rw").use { it.setLength(64L * 1024 * 1024) }
                                return observedLength
                            }
                        }
                        GameModCoordinateParser.parse(growingFile, "json")
                    }
                    else -> error("Unknown low heap validation mode")
                }
                error("Oversized coordinate metadata was accepted")
            } catch (error: GameModException) {
                check(error.code == "invalid_coordinates") { "Unexpected error ${error.code}" }
                println(error.code)
            }
        }
    }
}
