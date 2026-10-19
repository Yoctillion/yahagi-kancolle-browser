package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.zip.ZipFile

class GameModCoordinateParserTest {
    @Test fun `wedding crop origin dimensions and damaged variants are known optional fields`() {
        val result = parse("""{"api_mst_shipgraph":{"api_weda":[0,0],"api_wedb":[160,160],"api_wedc":[10,20],"api_wedd":[100,120]}}""", "json")
        assertEquals(setOf("api_weda", "api_wedb", "api_wedc", "api_wedd"), result.graph.keys)
    }
    @Test fun `JSON accepts only known integer coordinate pairs and ignores false empty metadata`() {
        val result = parse("""{"api_mst_ship":{"api_name":false,"api_getmes":"","api_sinfo":false},"api_mst_shipgraph":{"api_boko_n":[180,180],"api_weda":[0,-10]}}""", "json")
        assertEquals(mapOf("api_boko_n" to listOf(180, 180), "api_weda" to listOf(0, -10)), result.graph)
        assertFalse(result.metadataIgnored)
    }
    @Test fun `INI translation produces the same graph and zero is a real value`() {
        val result = parse("[info]\nship_name=\n[graph]\nboko_n_left=180\nboko_n_top=180\nweda_left=0\nweda_top=-10", "ini")
        assertEquals(mapOf("api_boko_n" to listOf(180, 180), "api_weda" to listOf(0, -10)), result.graph)
        assertFalse(result.metadataIgnored)
    }
    @Test fun `equivalent dual formats merge once while complementary fields remain`() {
        val ini = parse("[graph]\nboko_n_left=1\nboko_n_top=2", "ini")
        val json = parse("""{"api_mst_shipgraph":{"api_boko_n":[1,2],"api_battle_d":[3,4]}}""", "json")
        assertEquals(mapOf("api_boko_n" to listOf(1,2), "api_battle_d" to listOf(3,4)), GameModCoordinateParser.merge(listOf(ini, json)).graph)
    }
    @Test fun `conflicting dual formats are rejected explicitly`() {
        expect("coordinate_conflict") { GameModCoordinateParser.merge(listOf(
            parse("[graph]\nboko_n_left=1\nboko_n_top=2", "ini"),
            parse("""{"api_mst_shipgraph":{"api_boko_n":[1,3]}}""", "json"))) }
    }
    @Test fun `nonempty metadata is never applied and is reported as ignored`() {
        assertTrue(parse("""{"api_mst_ship":{"api_name":"Custom"},"api_mst_shipgraph":{"api_boko_n":[0,0]}}""", "json").metadataIgnored)
        assertTrue(parse("[info]\nship_name=Custom\n[graph]\nboko_n_left=0\nboko_n_top=0", "ini").metadataIgnored)
    }
    @Test fun `invalid JSON coordinate types and dimensions are rejected`() {
        listOf("[1.5,2]", "[true,2]", "[\"1\",2]", "[1]", "[1,2,3]", "false", "null", "[2147483648,0]").forEach { value ->
            expect("invalid_coordinates") { parse("{\"api_mst_shipgraph\":{\"api_boko_n\":$value}}", "json") }
        }
    }
    @Test fun `partial INI pair and conflicting duplicate values are rejected`() {
        expect("invalid_coordinates") { parse("[graph]\nboko_n_left=1", "ini") }
        expect("coordinate_conflict") { parse("[graph]\nboko_n_left=1\nboko_n_left=2\nboko_n_top=3", "ini") }
        expect("invalid_coordinates") { parse("[graph]\nboko_n_left=false\nboko_n_top=3", "ini") }
    }
    @Test fun `unknown fields never enter the payload and empty graphs are rejected`() {
        val result = parse("""{"api_mst_shipgraph":{"api_boko_n":[0,0],"api_filename":"evil"}}""", "json")
        assertTrue(result.unknownFields)
        assertEquals(setOf("api_boko_n"), result.graph.keys)
        expect("invalid_coordinates") { parse("{\"api_mst_shipgraph\":{}}", "json") }
        expect("invalid_coordinates") { parse("{\"frames\":{}}", "json") }
        expect("invalid_coordinates") { parse("not json", "json") }
    }
    @Test fun `oversized coordinate metadata is bounded before parsing`() {
        expect("invalid_coordinates") { parse(" ".repeat(131073), "json") }
    }
    @Test fun `real I47 JSON and INI agree on all fifteen graph fields`() {
        val configured = System.getenv("YAHAGI_REAL_MOD_ZIP") ?: return
        ZipFile(File(configured)).use { zip ->
            val data = zip.entries().asSequence().filter { it.name.endsWith(".config.ini") || it.name.endsWith(".config.json") }.map { entry ->
                GameModCoordinateParser.parse(zip.getInputStream(entry).use { it.readBytes() }, entry.name.substringAfterLast('.'))
            }.toList()
            assertEquals(2, data.size); assertEquals(15, data[0].graph.size); assertEquals(data[0].graph, data[1].graph)
            assertEquals(listOf(180,180), data[0].graph["api_boko_n"])
            assertEquals(listOf(20,240), data[0].graph["api_boko_d"])
            assertFalse(GameModCoordinateParser.merge(data).metadataIgnored)
        }
    }
    private fun parse(text: String, format: String) = GameModCoordinateParser.parse(text.toByteArray(), format)
    private fun expect(code: String, block: () -> Unit) {
        try { block(); fail("Expected $code") } catch (error: GameModException) { assertEquals(code, error.code) }
    }
}
