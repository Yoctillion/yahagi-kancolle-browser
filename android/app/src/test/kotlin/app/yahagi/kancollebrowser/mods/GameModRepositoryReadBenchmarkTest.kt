package app.yahagi.kancollebrowser.mods

import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Opt-in fixed-workload measurement; timing is evidence, never a pass/fail threshold. */
class GameModRepositoryReadBenchmarkTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun fixedInventoryRepeatedReadAndClose() {
        assumeTrue("Set YAHAGI_MOD_PERF_BENCHMARK=1", System.getenv("YAHAGI_MOD_PERF_BENCHMARK") == "1")
        val repository = GameModRepository(temporary.newFolder())
        val png = GameModRepositoryPerformanceTest.fixturePng()
        fun import(pack: Int) {
            val archive = ByteArrayOutputStream().also { output -> ZipOutputStream(output).use { zip ->
                repeat(32) { item -> zip.putNextEntry(ZipEntry("kcs2/img/benchmark/pack$pack/item$item.png")); zip.write(png); zip.closeEntry() }
            } }.toByteArray()
            val preview = repository.preflight(archive.inputStream(), "benchmark-$pack.zip")
            repository.commitLibraryImport(preview["token"] as String, UUID.nameUUIDFromBytes("benchmark-$pack".toByteArray()).toString())
        }
        repeat(4, ::import)
        @Suppress("UNCHECKED_CAST") val packages = repository.status()["packages"] as List<Map<String, Any?>>
        val ids = packages.map { it["id"] as String }
        val resources = packages.flatMap { entry -> (entry["resources"] as List<*>).map { (it as Map<*, *>)["id"] as String } }
        repository.saveDraft(mapOf("master" to true, "order" to ids, "enabledPackages" to ids, "enabledResources" to resources))
        repository.finishApply(repository.applyDraft())
        fun consume(index: Int) {
            val url = "https://w01x.kancolle-server.com/kcs2/img/benchmark/pack${index % 4}/item${index % 32}.png?version=1"
            val stream = requireNotNull(repository.openResource(url, "GET", emptyMap())).inputStream
            assertEquals(png.size, stream.use { it.readBytes().size })
        }
        repeat(40, ::consume)
        // Android's compile-time API has no java.lang.management, while the JVM runner
        // does. Reflection keeps this optional host measurement out of production APIs.
        val clockType = Class.forName("java.lang.management.ThreadMXBean")
        val clock = Class.forName("java.lang.management.ManagementFactory").getMethod("getThreadMXBean").invoke(null)
        fun cpuTime(): Long = runCatching { clockType.getMethod("getCurrentThreadCpuTime").invoke(clock) as Long }.getOrDefault(-1L)
        fun measure(scenario: String) {
            repeat(3) { trial ->
                val cpuStart = cpuTime()
                val wallStart = System.nanoTime()
                repeat(300, ::consume)
                val wallNanos = System.nanoTime() - wallStart
                val cpuNanos = if (cpuStart >= 0) cpuTime() - cpuStart else -1
                println("MOD_READ_BENCHMARK scenario=$scenario packages=4 resources=128 pngBytes=${png.size} iterations=300 trial=${trial + 1} wallNanos=$wallNanos threadCpuNanos=$cpuNanos")
            }
        }
        measure("steady")
        val oldStream = repository.openResource("https://w01x.kancolle-server.com/kcs2/img/benchmark/pack0/item0.png", "GET", emptyMap())!!.inputStream
        try {
            import(0); repository.finishApply(repository.applyDraft())
            repeat(40, ::consume)
            measure("old_lease_held")
        } finally { oldStream.close() }
    }
}
