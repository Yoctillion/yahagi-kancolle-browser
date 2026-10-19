package app.yahagi.kancollebrowser.mods

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.nio.file.Files
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/** A user-owned document tree. Paths are relative and never refer outside its root. */
interface GameModLibraryStore {
    val displayName: String
    val identity: String
    fun list(relative: String = ""): List<GameModLibraryEntry>
    fun openRead(relative: String): InputStream
    fun openWrite(relative: String): OutputStream
    fun createDirectory(relative: String)
    fun delete(relative: String): Boolean
    fun rename(from: String, to: String): Boolean
}

data class GameModLibraryEntry(val name: String, val isDirectory: Boolean, val size: Long = 0, val modified: Long = 0)
data class GameModLibraryCandidate(
    val id: String, val name: String, val archive: File, val status: String,
    val contentHash: String, val path: String,
)
data class GameModLibraryScan(val token: String, val items: List<Map<String, Any?>>, val cleanupCount: Int = 0) {
    fun toMap(): Map<String, Any?> = mapOf("token" to token, "items" to items, "cleanupCount" to cleanupCount)
}

class GameModLibrary(private val store: GameModLibraryStore, private val workspace: File) {
    private val gson = Gson()
    private var generation = 0L
    private var state: LibraryState
    private val scans = linkedMapOf<String, ScanPreview>()

    init {
        if (!workspace.isDirectory && !workspace.mkdirs()) fail("storage_error", "无法创建魔改库检查目录。")
        state = readState()
    }

    @Synchronized fun status(): Map<String, Any?> = linkedMapOf(
        "configured" to true, "location" to store.displayName, "identity" to store.identity,
        "packageCount" to state.packages.size, "restoreAvailable" to (state.applied != null),
        "packages" to state.packages.map { it.toMap() },
        "deletionFailures" to state.tombstones.filter { !it.cleaned }.map { it.id },
    )

    /** The same content fingerprint used by scans; timestamps and marker files are excluded. */
    fun fingerprintLocalTree(directory: File): String = localHash(directory)

    /** Inspection copies and validates every byte, but never changes the public directory. */
    @Synchronized fun scan(): GameModLibraryScan {
        if (scans.size >= 2) discardScan(scans.keys.first())
        val token = UUID.randomUUID().toString()
        val directory = stage("scan-$token")
        val prepared = mutableListOf<Prepared>()
        val archives = mutableListOf<SourceArchive>()
        val items = mutableListOf<MutableMap<String, Any?>>()
        val root = store.list().sortedBy { it.name }
        val known = state.packages.associateBy { it.id }
        val discovered = linkedMapOf<String, Prepared>()
        val seen = mutableSetOf<String>()
        var itemNumber = 0

        root.filter { it.isDirectory && !it.name.startsWith(".yahagi-") }.forEach { entry ->
            val path = safe(entry.name)
            try {
                val marker = readMarker(path)
                val located = state.packages.firstOrNull { it.path == path }
                if (located != null && marker != null && located.id != marker.id) {
                    fail("library_metadata_invalid", "已知魔改目录的包标识发生变化，请恢复其标记文件后重试。")
                }
                if (state.tombstones.any { !it.cleaned && (it.id == marker?.id || it.path == path) }) return@forEach
                val id = marker?.id ?: located?.id ?: UUID.randomUUID().toString()
                val previous = known[id]
                if (previous != null && previous.path != path && root.any { it.name == previous.path && it.isDirectory }) {
                    items.add(item(id, marker?.name ?: entry.name, path, "duplicate", marker?.contentHash, "同一包的旧目录或副本，已跳过。"))
                    return@forEach
                }
                if (!seen.add(id)) {
                    items.add(item(id, marker?.name ?: entry.name, path, "duplicate", marker?.contentHash, "存在相同魔改包标识，已跳过。"))
                    return@forEach
                }
                val local = File(directory, "${itemNumber++}").apply { mkdirs() }
                val tree = File(local, "tree").apply { mkdirs() }
                val hash = copyTree(path, tree)
                if (hashTree(path) != hash) fail("library_changed", "扫描期间文件发生变化，请复制完成后重试。")
                val archive = File(local, "package.zip")
                zipTree(tree, archive)
                val checked = validate(archive, marker?.name ?: entry.name, File(local, "validate"))
                val record = PackageRecord(id, marker?.name ?: previous?.name ?: entry.name, path, hash,
                    marker?.sourceZip ?: previous?.sourceZip, marker?.sourceHash ?: previous?.sourceHash,
                    sourceConsumed = marker?.sourceConsumed == true || previous?.sourceConsumed == true)
                val kind = if ((previous?.contentHash ?: marker?.contentHash) == hash) "unchanged"
                    else if (previous != null || marker != null) "updated" else "new"
                val row = item(id, record.name, path, kind, hash).apply {
                    put("resourceCount", checked.resources.size); put("supportedCount", checked.resources.count { it.supported })
                }
                val result = Prepared(record, archive, tree, path, hash, false, kind, row)
                prepared.add(result); discovered[id] = result; items.add(row)
            } catch (error: Exception) {
                val old = state.packages.firstOrNull { it.path == path }
                old?.let { seen.add(it.id) }
                items.add(item(old?.id, old?.name ?: entry.name, path, "invalid", null, message(error)))
            }
        }

        root.filter { !it.isDirectory && it.name.endsWith(".zip", true) }.forEach { entry ->
            val path = safe(entry.name)
            try {
                val local = File(directory, "${itemNumber++}").apply { mkdirs() }
                val archive = File(local, "package.zip")
                val sourceHash = store.openRead(path).use { source -> archive.outputStream().use { copyHashed(source, it, MAX_ARCHIVE) } }
                if (hashFile(path, MAX_ARCHIVE) != sourceHash) fail("library_changed", "ZIP 仍在复制，请完成后重新扫描。")
                if (state.tombstones.any { !it.cleaned && it.sourceZip == path && it.sourceHash == sourceHash }) return@forEach
                val previous = state.packages.firstOrNull { it.sourceZip == path && (!it.sourceConsumed || it.sourceHash == sourceHash) }
                    ?: discovered.values.firstOrNull { it.record.sourceZip == path && (!it.record.sourceConsumed || it.record.sourceHash == sourceHash) }?.record
                // An older import may still have its ZIP beside the editable directory.
                if (previous?.sourceHash == sourceHash) {
                    discovered[previous.id]?.let { archives.add(SourceArchive(it.record.id, path, sourceHash, it.record.contentHash)) }
                    return@forEach
                }
                val checked = validate(archive, entry.name.removeSuffixIgnoreCase(".zip"), File(local, "validate"))
                val tree = File(local, "tree").apply { mkdirs() }
                extractValidated(archive, tree)
                val hash = localHash(tree)
                val duplicate = discovered.values.firstOrNull { it.record.contentHash == hash && it.record.id != previous?.id }
                if (duplicate != null) {
                    items.add(item(duplicate.record.id, checked.name, path, "duplicate", hash, "内容与已有魔改包相同，已跳过。"))
                    return@forEach
                }
                val id = previous?.id ?: UUID.randomUUID().toString()
                val current = discovered[id]
                if (current != null && current.kind == "updated") {
                    prepared.remove(current); current.row["status"] = "invalid"; current.row["error"] = "解压目录和来源 ZIP 均已修改，请保留一种更新来源再扫描。"
                    items.add(item(id, previous?.name ?: checked.name, path, "invalid", hash, "解压目录和来源 ZIP 均已修改。"))
                    return@forEach
                }
                if (current != null) { prepared.remove(current); items.remove(current.row) }
                val kind = if (previous != null) "updated" else "new"
                val record = PackageRecord(id, previous?.name ?: checked.name, previous?.path ?: "", hash, path, sourceHash)
                val row = item(id, record.name, path, kind, hash).apply {
                    put("resourceCount", checked.resources.size); put("supportedCount", checked.resources.count { it.supported })
                }
                val normalized = File(local, "normalized.zip")
                zipTree(tree, normalized)
                val result = Prepared(record, normalized, tree, path, sourceHash, true, kind, row)
                prepared.add(result); discovered[id] = result; seen.add(id); items.add(row)
                archives.add(SourceArchive(id, path, sourceHash, hash))
            } catch (error: Exception) {
                val old = state.packages.firstOrNull { it.sourceZip == path }
                items.add(item(old?.id, old?.name ?: entry.name, path, "invalid", null, message(error)))
            }
        }

        state.packages.filter { it.id !in seen && state.tombstones.none { dead -> dead.id == it.id } }.forEach {
            items.add(item(it.id, it.name, it.path, "missing", it.contentHash, "公共目录中的文件已缺失，当前生效副本会保留。"))
        }
        // Different marker-less directories with identical content also remain a single import.
        val unique = mutableMapOf<String, Prepared>()
        prepared.toList().sortedBy { if (it.kind == "unchanged") 0 else 1 }.forEach { candidate ->
            val earlier = unique[candidate.record.contentHash]
            if (earlier != null && earlier.record.id != candidate.record.id) {
                prepared.remove(candidate); candidate.row["status"] = "duplicate"; candidate.row["error"] = "内容与已有魔改包相同，已跳过。"
            } else unique[candidate.record.contentHash] = candidate
        }
        val cleanup = archives.distinctBy { it.path }.filter { source -> prepared.any { it.record.id == source.id } }
        scans[token] = ScanPreview(directory, prepared, cleanup)
        return GameModLibraryScan(token, items.toList(), cleanup.size)
    }

    /** Recheck before accepting: a preview never gives permission to use subsequently changed files. */
    @Synchronized fun acceptScan(token: String): List<GameModLibraryCandidate> {
        val preview = scans[token] ?: fail("invalid_token", "扫描预览已失效，请重新扫描。")
        preview.prepared.forEach {
            val current = if (it.zip) hashFile(it.sourcePath, MAX_ARCHIVE) else hashTree(it.sourcePath)
            if (current != it.sourceHash) fail("library_changed", "预览后魔改文件发生变化，请重新扫描。")
        }
        val results = mutableListOf<GameModLibraryCandidate>()
        preview.prepared.forEach { candidate ->
            val record = if (candidate.zip) saveTree(candidate.record, candidate.tree) else {
                writeMarker(candidate.record)
                updateRecord(candidate.record)
                candidate.record
            }
            results.add(GameModLibraryCandidate(record.id, record.name, candidate.archive, candidate.kind, record.contentHash, record.path))
        }
        // Keep returned local archives alive until the next preview/discard, for repository preflight.
        return results
    }

    @Synchronized fun discardScan(token: String) {
        scans.remove(token)?.directory?.deleteRecursively()
    }

    /** Only after the complete repository import succeeds; previews and failed imports keep their ZIPs. */
    @Synchronized fun completeScan(token: String): List<String> {
        val preview = scans[token] ?: fail("invalid_token", "扫描预览已失效，请重新扫描。")
        return preview.archives.mapNotNull { source ->
            try {
                val path = safe(source.path)
                if (path.contains('/') || !path.endsWith(".zip", true)) fail("unsafe_path", "来源 ZIP 必须位于魔改库根目录。")
                val entry = store.list().firstOrNull { it.name == path } ?: return@mapNotNull null
                val record = state.packages.singleOrNull { it.id == source.id }
                if (entry.isDirectory || record == null || record.contentHash != source.contentHash ||
                    readMarker(record.path)?.id != source.id || hashTree(record.path) != source.contentHash ||
                    hashFile(path, MAX_ARCHIVE) != source.hash) return@mapNotNull path
                if (!record.sourceConsumed) {
                    // Keep ownership for failed-delete retries, but a later unrelated cache.zip
                    // must not update this package merely because it reuses the filename.
                    val consumed = record.copy(sourceConsumed = true)
                    writeMarker(consumed)
                    updateRecord(consumed)
                }
                if (hashFile(path, MAX_ARCHIVE) != source.hash || !store.delete(path)) path else null
            } catch (_: Exception) { source.path }
        }
    }

    @Synchronized fun savePackage(id: String, name: String, directory: File, sourceZip: String? = null, sourceHash: String? = null): Map<String, Any?> {
        requireUuid(id)
        if (sourceZip != null && (safe(sourceZip).contains('/') || !sourceZip.endsWith(".zip", true))) fail("unsafe_path", "来源 ZIP 必须位于魔改库根目录。")
        if (sourceHash != null && !HASH.matches(sourceHash)) fail("invalid_config", "来源 ZIP 指纹无效。")
        val local = stage("save")
        try {
            val archive = File(local, "check.zip")
            zipTree(directory, archive)
            validate(archive, name, File(local, "validate"))
            val hash = localHash(directory)
            val previous = state.packages.firstOrNull { it.id == id }
            val record = saveTree(PackageRecord(id, name.trim().take(160).ifEmpty { "魔改包" }, previous?.path ?: "", hash, sourceZip, sourceHash), directory)
            return record.toMap()
        } finally { local.deleteRecursively() }
    }

    @Synchronized fun saveAppliedConfiguration(config: Map<*, *>) {
        @Suppress("UNCHECKED_CAST")
        val copied = gson.fromJson(gson.toJson(config), Map::class.java) as Map<String, Any?>
        saveState(state.copy(applied = copied))
    }

    @Synchronized fun appliedConfiguration(): Map<String, Any?>? {
        @Suppress("UNCHECKED_CAST")
        return state.applied?.let { gson.fromJson(gson.toJson(it), Map::class.java) as Map<String, Any?> }
    }

    /** Call only after an apply succeeds. Tombstones are durable before any public file is removed. */
    @Synchronized fun deletePackages(ids: List<String>): List<String> {
        ids.forEach(::requireUuid)
        val records = state.packages.filter { it.id in ids }
        val dead = (state.tombstones + records.map { record ->
            val source = record.sourceZip?.takeUnless { zip -> record.sourceConsumed &&
                runCatching { !exists(zip) || hashFile(zip, MAX_ARCHIVE) != record.sourceHash }.getOrDefault(false) }
            Tombstone(record.id, record.path, source, record.sourceHash)
        }).distinctBy { it.id }
        saveState(state.copy(packages = state.packages.filterNot { it.id in ids }, tombstones = dead))
        val failures = mutableListOf<String>()
        val cleaned = state.tombstones.map { tombstone ->
            if (tombstone.id !in ids || tombstone.cleaned) return@map tombstone
            var complete = true
            if (exists(tombstone.path)) {
                try {
                    if (readMarker(tombstone.path)?.id != tombstone.id || !store.delete(tombstone.path)) {
                        failures.add(tombstone.path); complete = false
                    }
                } catch (_: Exception) { failures.add(tombstone.path); complete = false }
            }
            tombstone.sourceZip?.let { source ->
                if (exists(source)) try {
                    if (hashFile(source, MAX_ARCHIVE) != tombstone.sourceHash || !store.delete(source)) {
                        failures.add(source); complete = false
                    }
                } catch (_: Exception) { failures.add(source); complete = false }
            }
            tombstone.copy(cleaned = complete)
        }
        saveState(state.copy(tombstones = cleaned))
        return failures.distinct()
    }

    private fun saveTree(record: PackageRecord, tree: File): PackageRecord {
        val previous = state.packages.firstOrNull { it.id == record.id }
        val ownsPrevious = previous != null && exists(previous.path) && runCatching { readMarker(previous.path)?.id == previous.id }.getOrDefault(false)
        if (previous != null && ownsPrevious && previous.contentHash == record.contentHash && hashTree(previous.path) == record.contentHash) {
            val same = record.copy(path = previous.path); writeMarker(same); updateRecord(same); return same
        }
        val safeName = record.name.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_").trim().take(64).ifEmpty { "魔改包" }
        var destination = "$safeName-${record.id.take(8)}-${record.contentHash.take(8)}"
        if (exists(destination)) destination += "-${UUID.randomUUID().toString().take(8)}"
        val temporary = ".yahagi-import-${UUID.randomUUID()}"
        store.createDirectory(temporary)
        try {
            copyLocalToStore(tree, temporary)
            val staged = record.copy(path = temporary)
            if (hashTree(temporary) != record.contentHash) fail("storage_error", "魔改库写入校验失败。")
            writeMarker(staged)
            if (!store.rename(temporary, destination)) {
                // Providers without rename still publish only after every resource has been verified.
                store.createDirectory(destination)
                copyLocalToStore(tree, destination)
                if (hashTree(destination) != record.contentHash) fail("storage_error", "魔改库写入校验失败。")
                writeMarker(record.copy(path = destination))
                store.delete(temporary)
            }
            val saved = record.copy(path = destination)
            writeMarker(saved) // A renamed marker must describe its final location.
            updateRecord(saved)
            if (ownsPrevious && previous != null && previous.path != saved.path) store.delete(previous.path)
            return saved
        } catch (error: Exception) {
            store.delete(temporary)
            // A complete public directory is intentionally retained if only its index write failed.
            if (error is GameModException) throw error
            fail("storage_error", "无法保存公共魔改文件：${message(error)}")
        }
    }

    private fun updateRecord(record: PackageRecord) {
        saveState(state.copy(packages = state.packages.filterNot { it.id == record.id } + record,
            tombstones = state.tombstones.filterNot { it.id == record.id }))
    }

    private fun writeMarker(record: PackageRecord) {
        writeBytes("${safe(record.path)}/$MARKER", gson.toJson(record).toByteArray(Charsets.UTF_8))
    }

    private fun readMarker(directory: String): PackageRecord? {
        val entry = store.list(directory).firstOrNull { it.name == MARKER } ?: return null
        if (entry.isDirectory || entry.size > MAX_METADATA) fail("library_metadata_invalid", "魔改包标记文件无效。")
        try {
            val value = gson.fromJson(readText("$directory/$MARKER"), PackageRecord::class.java)
            requireUuid(value.id)
            if (value.schemaVersion != 1 || value.name.isBlank() || !HASH.matches(value.contentHash)) fail("library_metadata_invalid", "魔改包标记文件版本或内容无效。")
            value.sourceZip?.let { if (safe(it).contains('/') || !it.endsWith(".zip", true)) fail("unsafe_path", "魔改包来源路径无效。") }
            value.sourceHash?.let { if (!HASH.matches(it)) fail("library_metadata_invalid", "魔改包来源校验无效。") }
            return value.copy(path = directory)
        } catch (error: Exception) {
            if (error is GameModException) throw error
            fail("library_metadata_invalid", "魔改包标记文件已损坏。")
        }
    }

    private fun readState(): LibraryState {
        val present = store.list().filter { it.name in STATE_FILES && !it.isDirectory }
        if (present.isEmpty()) return LibraryState()
        val valid = present.mapNotNull { entry ->
            try {
                val envelope = JsonParser.parseString(readText(entry.name)).asJsonObject
                val payload = envelope.getAsJsonObject("state")
                val encoded = payload.toString().toByteArray(Charsets.UTF_8)
                if (envelope["schemaVersion"].asInt != 1 || envelope["sha256"].asString != digest(encoded)) return@mapNotNull null
                val decoded = gson.fromJson(payload, LibraryState::class.java)
                if (decoded.schemaVersion != 1 || payload["packages"]?.isJsonArray != true || payload["tombstones"]?.isJsonArray != true) return@mapNotNull null
                decoded.packages.forEach { requireUuid(it.id); safe(it.path); if (!HASH.matches(it.contentHash)) fail("library_metadata_invalid", "魔改库记录校验无效。") }
                decoded.tombstones.forEach { requireUuid(it.id); safe(it.path) }
                envelope["generation"].asLong to decoded
            } catch (_: Exception) { null }
        }.maxByOrNull { it.first } ?: fail("library_metadata_invalid", "魔改库配置已损坏，公共资源仍保留，请恢复 library.json 备份。")
        generation = valid.first
        return valid.second
    }

    private fun saveState(next: LibraryState) {
        val nextGeneration = generation + 1
        val payload = gson.toJsonTree(next).asJsonObject
        val envelope = JsonObject().apply {
            addProperty("schemaVersion", 1); addProperty("generation", nextGeneration)
            addProperty("sha256", digest(payload.toString().toByteArray(Charsets.UTF_8))); add("state", payload)
        }
        val name = STATE_FILES[((nextGeneration - 1) % STATE_FILES.size).toInt()]
        val bytes = envelope.toString().toByteArray(Charsets.UTF_8)
        try {
            writeBytes(name, bytes)
            if (!store.openRead(name).use { it.readBytesLimited(MAX_METADATA) }.contentEquals(bytes)) fail("storage_error", "魔改库配置写入校验失败。")
        } catch (error: Exception) {
            if (error is GameModException) throw error
            fail("storage_error", "无法保存魔改库配置：${message(error)}")
        }
        state = next; generation = nextGeneration
    }

    private fun copyTree(path: String, destination: File): String {
        val files = treeFiles(path)
        val digest = MessageDigest.getInstance("SHA-256")
        var total = 0L
        files.forEach { relative ->
            val file = File(destination, relative).apply { parentFile?.mkdirs() }
            digestName(digest, relative)
            val fileDigest = MessageDigest.getInstance("SHA-256")
            store.openRead("$path/$relative").use { source -> file.outputStream().use { output ->
                val size = copyDigest(source, output, fileDigest, MAX_FILE); total += size
                if (total > MAX_TREE) fail("quota_exceeded", "魔改包总大小不能超过 1 GiB。")
            } }
            digest.update(fileDigest.digest())
            digest.update(0)
        }
        return hex(digest.digest())
    }

    private fun hashTree(path: String): String {
        val digest = MessageDigest.getInstance("SHA-256"); var total = 0L
        treeFiles(path).forEach { relative ->
            digestName(digest, relative)
            val fileDigest = MessageDigest.getInstance("SHA-256")
            store.openRead("$path/$relative").use { total += copyDigest(it, null, fileDigest, MAX_FILE) }
            if (total > MAX_TREE) fail("quota_exceeded", "魔改包总大小不能超过 1 GiB。")
            digest.update(fileDigest.digest())
            digest.update(0)
        }
        return hex(digest.digest())
    }

    private fun treeFiles(path: String): List<String> {
        val files = mutableListOf<String>()
        var count = 0
        fun walk(directory: String, prefix: String, depth: Int) {
            if (depth > 64) fail("quota_exceeded", "魔改目录层级过多。")
            val entries = store.list(directory)
            count += entries.size
            if (count > MAX_ENTRIES) fail("quota_exceeded", "魔改目录条目数量不能超过 20000。")
            if (entries.map { it.name }.distinct().size != entries.size) fail("duplicate_resource", "魔改目录含同名文件。")
            entries.forEach { entry ->
                if (prefix.isEmpty() && entry.name == MARKER) return@forEach
                val name = safe(entry.name)
                if ('/' in name) fail("unsafe_path", "魔改文件名不能包含路径。")
                val relative = prefix + name
                if (entry.isDirectory) walk("$directory/$name", "$relative/", depth + 1)
                else { if (entry.size > MAX_FILE) fail("quota_exceeded", "单个魔改文件不能超过 64 MiB。"); files.add(relative) }
                if (files.size > MAX_ENTRIES) fail("quota_exceeded", "魔改文件数量不能超过 20000。")
            }
        }
        walk(path, "", 0)
        if (files.isEmpty()) fail("invalid_archive", "魔改目录中没有文件。")
        return files.sorted()
    }

    private fun localHash(directory: File): String = hashLocal(directory).first
    private fun hashLocal(directory: File): Pair<String, List<File>> {
        val fileStore = GameModFileLibraryStore(directory)
        val files = mutableListOf<File>()
        val digest = MessageDigest.getInstance("SHA-256"); var total = 0L
        var count = 0
        fun visit(path: String, depth: Int) {
            if (depth > 64) fail("quota_exceeded", "魔改目录层级过多。")
            val entries = fileStore.list(path).sortedBy { it.name }
            count += entries.size
            if (count > MAX_ENTRIES) fail("quota_exceeded", "魔改目录条目数量不能超过 20000。")
            entries.forEach { entry ->
                val relative = if (path.isEmpty()) entry.name else "$path/${entry.name}"
                if (relative == MARKER) return@forEach
                if (entry.isDirectory) visit(relative, depth + 1) else files.add(File(directory, relative))
            }
        }
        visit("", 0)
        if (files.isEmpty() || files.size > MAX_ENTRIES) fail("quota_exceeded", "魔改包文件数量无效。")
        files.sortBy { it.relativeTo(directory).invariantSeparatorsPath }
        files.forEach { file ->
            val relative = file.relativeTo(directory).invariantSeparatorsPath
            digestName(digest, relative)
            val fileDigest = MessageDigest.getInstance("SHA-256")
            fileStore.openRead(relative).use { total += copyDigest(it, null, fileDigest, MAX_FILE) }
            if (total > MAX_TREE) fail("quota_exceeded", "魔改包总大小不能超过 1 GiB。")
            digest.update(fileDigest.digest())
            digest.update(0)
        }
        return hex(digest.digest()) to files
    }

    private fun zipTree(tree: File, archive: File) {
        val files = hashLocal(tree).second
        ZipOutputStream(archive.outputStream().buffered()).use { zip ->
            // Compression-free staging avoids imposing extra ratio restrictions on already validated images.
            zip.setLevel(0)
            files.forEach { file ->
                zip.putNextEntry(ZipEntry(file.relativeTo(tree).invariantSeparatorsPath))
                file.inputStream().use { it.copyTo(zip) }; zip.closeEntry()
            }
        }
        if (archive.length() > GAME_MOD_LIBRARY_ARCHIVE_LIMIT) fail("quota_exceeded", "魔改库内部检查文件超过限额。")
    }

    private fun validate(archive: File, name: String, directory: File): ArchiveResult {
        val result = archive.inputStream().use { GameModArchive().unpackLibrary(it, "$name.zip", directory) }
        if (result.resources.none { it.supported }) fail("unsupported_archive", "未找到受支持的游戏资源，请保留 kcs/kcs2 文件夹结构。")
        return result
    }

    private fun extractValidated(archive: File, tree: File) {
        ZipFile(archive).use { zip ->
            val entries = zip.entries()
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                if (entry.isDirectory) continue
                var path = entry.name.replace('\\', '/').split('/').filter { it.isNotEmpty() }
                if (path.firstOrNull() == "cache") path = path.drop(1)
                val normalized = safe(path.joinToString("/").replace(Regex("\\.hack\\.([A-Za-z0-9]+)$"), ".$1"))
                if (normalized == MARKER) fail("unsafe_path", "ZIP 不能覆盖魔改包标记。")
                val destination = File(tree, normalized).apply { parentFile?.mkdirs() }
                zip.getInputStream(entry).use { source -> destination.outputStream().use { copyDigest(source, it, MessageDigest.getInstance("SHA-256"), MAX_FILE) } }
            }
        }
    }

    private fun copyLocalToStore(tree: File, destination: String) {
        hashLocal(tree).second.forEach { file ->
            val relative = file.relativeTo(tree).invariantSeparatorsPath
            val parent = relative.substringBeforeLast('/', "")
            if (parent.isNotEmpty()) store.createDirectory("$destination/$parent")
            file.inputStream().use { source -> store.openWrite("$destination/$relative").use { source.copyTo(it) } }
        }
    }

    private fun exists(path: String): Boolean {
        val checked = safe(path)
        return store.list(checked.substringBeforeLast('/', "")).any { it.name == checked.substringAfterLast('/') }
    }
    private fun hashFile(path: String, limit: Long): String = store.openRead(safe(path)).use { copyHashed(it, null, limit) }
    private fun writeBytes(path: String, bytes: ByteArray) = store.openWrite(safe(path)).use { it.write(bytes) }
    private fun readText(path: String): String = store.openRead(safe(path)).use { it.readBytesLimited(MAX_METADATA).toString(Charsets.UTF_8) }
    private fun stage(name: String): File = File(workspace, "$name-${UUID.randomUUID()}").apply { if (!mkdirs()) fail("storage_error", "无法准备魔改库临时目录。") }
    private fun item(id: String?, name: String, path: String, status: String, hash: String?, error: String? = null): MutableMap<String, Any?> = linkedMapOf(
        "id" to id, "name" to name, "path" to path, "status" to status, "contentHash" to hash,
        "error" to error, "reason" to error,
    )

    private data class LibraryState(val schemaVersion: Int = 1, val packages: List<PackageRecord> = emptyList(), val applied: Map<String, Any?>? = null, val tombstones: List<Tombstone> = emptyList())
    private data class PackageRecord(val id: String, val name: String, val path: String, val contentHash: String, val sourceZip: String? = null, val sourceHash: String? = null, val schemaVersion: Int = 1, val sourceConsumed: Boolean = false) {
        fun toMap(): Map<String, Any?> = linkedMapOf("id" to id, "name" to name, "path" to path, "contentHash" to contentHash, "sourceZip" to sourceZip, "sourceHash" to sourceHash)
    }
    private data class Tombstone(val id: String, val path: String, val sourceZip: String? = null, val sourceHash: String? = null, val cleaned: Boolean = false)
    private data class Prepared(val record: PackageRecord, val archive: File, val tree: File, val sourcePath: String, val sourceHash: String, val zip: Boolean, val kind: String, val row: MutableMap<String, Any?>)
    private data class SourceArchive(val id: String, val path: String, val hash: String, val contentHash: String)
    private data class ScanPreview(val directory: File, val prepared: List<Prepared>, val archives: List<SourceArchive>)

    private companion object {
        const val MARKER = ".yahagi-package.json"
        val STATE_FILES = listOf("library.json", ".yahagi-library-backup.json")
        val HASH = Regex("[0-9a-f]{64}")
        const val MAX_ARCHIVE = 256L * 1024 * 1024
        const val MAX_FILE = 64L * 1024 * 1024
        const val MAX_TREE = 1024L * 1024 * 1024
        const val MAX_METADATA = 4L * 1024 * 1024
        const val MAX_ENTRIES = 20_000
        fun message(error: Exception): String = (error.message ?: "文件读取失败。 ").take(300)
        fun fail(code: String, message: String): Nothing = throw GameModException(code, message)
        fun requireUuid(id: String) { if (runCatching { UUID.fromString(id).toString() == id.lowercase() }.getOrDefault(false).not()) fail("invalid_config", "魔改包标识无效。") }
        fun safe(relative: String): String {
            if (relative.isEmpty() || relative.length > 4096 || relative.startsWith('/') || relative.any { it.code < 32 || it in "\\:%?#" } || relative.split('/').any { it.isEmpty() || it == "." || it == ".." || it.length > 255 }) fail("unsafe_path", "魔改库包含不安全的相对路径。")
            return relative
        }
        fun digest(bytes: ByteArray): String = hex(MessageDigest.getInstance("SHA-256").digest(bytes))
        fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
        fun digestName(digest: MessageDigest, name: String) { digest.update(name.toByteArray(Charsets.UTF_8)); digest.update(0) }
        fun copyHashed(input: InputStream, output: OutputStream?, limit: Long): String {
            val digest = MessageDigest.getInstance("SHA-256"); copyDigest(input, output, digest, limit); return hex(digest.digest())
        }
        fun copyDigest(input: InputStream, output: OutputStream?, digest: MessageDigest, limit: Long): Long {
            val buffer = ByteArray(32 * 1024); var total = 0L
            while (true) { val count = input.read(buffer); if (count < 0) break; if (count == 0) continue
                total += count; if (total > limit) fail("quota_exceeded", "魔改文件超过大小限制。")
                digest.update(buffer, 0, count); output?.write(buffer, 0, count)
            }
            return total
        }
        fun InputStream.readBytesLimited(limit: Long): ByteArray = java.io.ByteArrayOutputStream().also { copyDigest(this, it, MessageDigest.getInstance("SHA-256"), limit) }.toByteArray()
        fun String.removeSuffixIgnoreCase(suffix: String): String = if (endsWith(suffix, true)) dropLast(suffix.length) else this
    }
}

class GameModFileLibraryStore(private val root: File) : GameModLibraryStore {
    override val displayName: String get() = root.absolutePath
    override val identity: String get() = root.canonicalPath
    init { if ((!root.isDirectory && !root.mkdirs()) || Files.isSymbolicLink(root.toPath())) throw GameModException("storage_error", "无法创建魔改库目录。") }
    override fun list(relative: String): List<GameModLibraryEntry> = resolve(relative, true).let { directory ->
        if (!directory.isDirectory) throw GameModException("storage_error", "魔改库目录不存在。")
        directory.listFiles()?.map { file ->
            val checked = resolve(if (relative.isEmpty()) file.name else "$relative/${file.name}")
            GameModLibraryEntry(checked.name, checked.isDirectory, if (checked.isFile) checked.length() else 0, checked.lastModified())
        } ?: throw GameModException("storage_error", "无法读取魔改库目录。")
    }
    override fun openRead(relative: String): InputStream = resolve(relative).let { if (!it.isFile) throw GameModException("storage_error", "魔改文件不存在。"); it.inputStream() }
    override fun openWrite(relative: String): OutputStream = resolve(relative).let { if (it.parentFile?.isDirectory != true) throw GameModException("storage_error", "魔改文件夹不存在。"); it.outputStream() }
    override fun createDirectory(relative: String) { val directory=resolve(relative); if (!directory.isDirectory && !directory.mkdirs()) throw GameModException("storage_error", "无法创建魔改文件夹。") }
    override fun delete(relative: String): Boolean {
        val target = resolve(relative)
        if (!target.exists()) return true
        fun remove(file: File): Boolean {
            resolve(file.relativeTo(root).invariantSeparatorsPath)
            if (file.isDirectory && file.listFiles()?.all(::remove) != true) return false
            return file.delete()
        }
        return remove(target)
    }
    override fun rename(from: String, to: String): Boolean { val source=resolve(from);val target=resolve(to);return !target.exists() && source.renameTo(target) }
    private fun resolve(relative: String, allowRoot: Boolean = false): File {
        if (relative.isEmpty() && allowRoot) return root
        if (relative.isEmpty() || relative.startsWith('/') || relative.any {it.code<32 || it in "\\:%?#"} || relative.split('/').any {it.isEmpty()||it=="."||it==".."}) throw GameModException("unsafe_path", "魔改库路径不安全。")
        val file=File(root,relative).absoluteFile.normalize();val canonical=file.canonicalFile;val base=root.canonicalFile
        if (!canonical.path.startsWith(base.path+File.separator)) throw GameModException("unsafe_path", "魔改库路径越界。")
        var part=root.absoluteFile
        relative.split('/').forEach {part=File(part,it);if(Files.isSymbolicLink(part.toPath()))throw GameModException("unsafe_path","魔改库不能包含符号链接。")}
        return file
    }
}
