package app.yahagi.kancollebrowser.mods

import java.io.File
import java.io.InputStream
import java.io.RandomAccessFile
import java.util.zip.CRC32
import java.util.zip.ZipFile

internal const val GAME_MOD_LIBRARY_ARCHIVE_LIMIT = 1024L * 1024 * 1024 + 16L * 1024 * 1024

internal data class ArchiveResult(
    val name: String,
    val sizeBytes: Long,
    val resources: List<ArchiveResource>,
    val warnings: List<String>,
)

internal data class ArchiveResource(
    val path: String,
    val kind: String,
    val label: String,
    val supported: Boolean,
    val reason: String?,
    val groupId: String?,
    val relativeFile: String,
    val sourcePaths: List<String> = listOf(path),
    val coordinateShipId: String? = null,
    val coordinateGraph: Map<String, List<Int>> = emptyMap(),
)

internal class GameModArchive(private val progress: GameModProgress? = null) {
    fun unpackLibrary(input: InputStream, sourceName: String, directory: File): ArchiveResult =
        unpackChecked(input, sourceName, directory, GAME_MOD_LIBRARY_ARCHIVE_LIMIT)

    fun unpack(input: InputStream, sourceName: String, directory: File): ArchiveResult =
        unpackChecked(input, sourceName, directory, MAX_ARCHIVE_BYTES)

    private fun unpackChecked(input: InputStream, sourceName: String, directory: File, archiveLimit: Long): ArchiveResult {
        if ((!directory.isDirectory && !directory.mkdirs()) || directory.listFiles()?.isNotEmpty() == true) {
            throw GameModException("invalid_archive", "导入临时目录必须为空。")
        }
        val archive = File.createTempFile("archive-", ".zip", directory)
        val files = File(directory, "files")
        val written = mutableListOf<File>()
        try {
            progress?.update(phase = "read")
            progress?.files(0, null, null, 0L, null)
            archive.outputStream().buffered().use { output ->
                val buffer = ByteArray(8192)
                var compressed = 0L
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    compressed += count
                    requireQuota(compressed <= archiveLimit, if (archiveLimit == MAX_ARCHIVE_BYTES) "ZIP 不能超过 256 MiB。" else "魔改库内部检查文件超过限额。")
                    output.write(buffer, 0, count)
                    progress?.files(0, null, null, compressed, null)
                }
            }
            val expectedEntries = checkCentralDirectory(archive)
            val normalizedPaths = mutableSetOf<String>()
            val resources = mutableListOf<ArchiveResource>()
            val formatWarnings = linkedSetOf<String>()
            var expanded = 0L
            var decoded = 0L
            if (!files.mkdir()) throw GameModException("invalid_archive", "无法创建导入目录。")
            ZipFile(archive).use { zip ->
                val fileTotal = zip.entries().asSequence().count { !it.name.replace('\\', '/').endsWith('/') }
                val byteTotal = zip.entries().asSequence().filter { !it.name.replace('\\', '/').endsWith('/') }
                    .sumOf { it.size.coerceAtLeast(0L) }.takeIf { it <= MAX_EXPANDED_BYTES }
                var completedFiles = 0
                progress?.update(phase = "validate")
                progress?.files(0, fileTotal, null, 0L, byteTotal)
                val entries = zip.entries()
                var count = 0
                while (entries.hasMoreElements()) {
                    val entry = entries.nextElement()
                    count++
                    requireQuota(count <= MAX_ENTRIES, "ZIP 文件数量不能超过 20000。")
                    val sourcePath = normalizePath(entry.name)
                    val wav = WAV_PATH.matches(sourcePath)
                    val path = if (wav) sourcePath.dropLast(4) + ".mp3" else sourcePath
                    val isDirectory = entry.name.replace('\\', '/').endsWith('/')
                    if (path.isNotEmpty() && !normalizedPaths.add(path)) {
                        throw GameModException("duplicate_resource", "ZIP 中存在相同目标资源：$path")
                    }
                    if (isDirectory) {
                        if (entry.size != 0L) throw GameModException("invalid_archive", "目录条目包含数据。")
                        continue
                    }
                    if (path.isEmpty()) throw GameModException("unsafe_path", "资源路径为空。")
                    requireQuota(entry.size in 0..MAX_FILE_BYTES, "单个文件不能超过 64 MiB。")
                    requireQuota(entry.compressedSize >= 0 && entry.size <= entry.compressedSize.coerceAtLeast(1) * MAX_RATIO,
                        "文件解压比例超过 200。")
                    val extension = sourcePath.substringAfterLast('.', "bin").takeIf { it.matches(Regex("[A-Za-z0-9]{1,8}")) } ?: "bin"
                    val relativeFile = "files/${resources.size}.$extension"
                    val target = File(directory, relativeFile)
                    progress?.files(completedFiles, fileTotal, path, expanded, byteTotal)
                    written.add(target)
                    var actual = 0L
                    val crc = CRC32()
                    zip.getInputStream(entry).use { source ->
                        target.outputStream().buffered().use { output ->
                            val buffer = ByteArray(8192)
                            while (true) {
                                val read = source.read(buffer)
                                if (read < 0) break
                                if (read == 0) continue
                                actual += read
                                expanded += read
                                requireQuota(actual <= MAX_FILE_BYTES && expanded <= MAX_EXPANDED_BYTES,
                                    "ZIP 解压大小超过限额。")
                                requireQuota(actual <= entry.compressedSize.coerceAtLeast(1) * MAX_RATIO,
                                    "文件实际解压比例超过 200。")
                                crc.update(buffer, 0, read)
                                output.write(buffer, 0, read)
                                progress?.files(completedFiles, fileTotal, path, expanded, byteTotal)
                            }
                        }
                    }
                    if (actual != entry.size || crc.value != entry.crc) {
                        throw GameModException("invalid_archive", "ZIP 文件长度或校验和错误：$path")
                    }
                    if (path.endsWith(".png", ignoreCase = true)) {
                        val originalLength = target.length()
                        decoded += GameModPng.validateImport(target)
                        if (target.length() != originalLength) formatWarnings.add("png_trailing_data_removed")
                        requireQuota(decoded <= MAX_EXPANDED_BYTES, "PNG 解码总大小超过 1 GiB。")
                    }
                    if (wav) GameModWav.validate(target)
                    else if (AUDIO_PATH.matches(path)) GameModMp3.validate(target)
                    resources.add(classify(path, relativeFile).copy(sourcePaths = listOf(entry.name.replace('\\', '/'))))
                    completedFiles++
                    progress?.files(completedFiles, fileTotal, path, expanded, byteTotal)
                }
                if (count != expectedEntries) throw GameModException("invalid_archive", "ZIP 目录不完整。")
            }
            if (resources.any { BAT_PATH.matches(it.path) } && resources.none { it.supported }) {
                throw GameModException("unsupported_archive", "这是 bat.zip 中间格式，请先用制作网站的图片批处理导出 cache.zip。")
            }
            val (checkedResources, warnings) = applyDependencies(resources, directory)
            if (checkedResources.map { it.path }.distinct().size != checkedResources.size) {
                throw GameModException("duplicate_resource", "ZIP 中的逻辑资源目标重复。")
            }
            val basename = sourceName.replace('\\', '/').substringAfterLast('/').let {
                if (it.endsWith(".zip", ignoreCase = true)) it.dropLast(4) else it
            }.trim().take(160).ifEmpty { "魔改包" }
            return ArchiveResult(basename, expanded, checkedResources, (formatWarnings + warnings).distinct())
        } catch (error: Exception) {
            written.forEach { it.delete() }
            files.delete()
            if (error is GameModException) throw error
            throw GameModException("invalid_archive", "ZIP 已损坏或格式不受支持。")
        } finally {
            archive.delete()
        }
    }

    /** Inspect central attributes which java.util.zip.ZipEntry does not expose on Android. */
    private fun checkCentralDirectory(file: File): Int = RandomAccessFile(file, "r").use { input ->
        if (input.length() >= 6) {
            val signature = ByteArray(6); input.readFully(signature)
            if (signature.contentEquals(byteArrayOf(0x37, 0x7a, 0xbc.toByte(), 0xaf.toByte(), 0x27, 0x1c))) {
                throw GameModException("seven_zip_unsupported", "请先将 7z 转换成保留目录结构的 ZIP。")
            }
        }
        if (input.length() < 22) throw GameModException("invalid_archive", "不是完整的 ZIP 文件。")
        val tailSize = minOf(input.length(), 65_557L).toInt()
        val tail = ByteArray(tailSize)
        input.seek(input.length() - tailSize)
        input.readFully(tail)
        val end = (tail.size - 22 downTo 0).firstOrNull {
            uint(tail, it) == 0x06054b50L && it + 22 + ushort(tail, it + 20) == tail.size
        } ?: throw GameModException("invalid_archive", "ZIP 目录缺失。")
        val count = ushort(tail, end + 10)
        requireQuota(count <= MAX_ENTRIES, "ZIP 文件数量不能超过 20000。")
        if (ushort(tail, end + 4) != 0 || ushort(tail, end + 6) != 0 || ushort(tail, end + 8) != count) {
            throw GameModException("invalid_archive", "不支持分卷 ZIP。")
        }
        val size = uint(tail, end + 12)
        val offset = uint(tail, end + 16)
        val endOffset = input.length() - tailSize + end
        if (size == 0xffffffffL || offset == 0xffffffffL || offset + size != endOffset) {
            throw GameModException("invalid_archive", "不支持 ZIP64 或无效的 ZIP 目录。")
        }
        val localRanges = mutableListOf<Pair<Long, Long>>()
        input.seek(offset)
        repeat(count) {
            if (input.filePointer + 46 > endOffset) throw GameModException("invalid_archive", "ZIP 目录被截断。")
            val header = ByteArray(46)
            input.readFully(header)
            if (uint(header, 0) != 0x02014b50L) throw GameModException("invalid_archive", "ZIP 目录无效。")
            val flags = ushort(header, 8)
            val method = ushort(header, 10)
            if (flags and 0x2041 != 0 || method !in listOf(0, 8)) {
                throw GameModException("unsupported_archive", "不支持加密 ZIP 或此压缩算法。")
            }
            val mode = (uint(header, 38) ushr 16).toInt() and 0xf000
            if (mode != 0 && mode != 0x8000 && mode != 0x4000) {
                throw GameModException("unsafe_path", "ZIP 中不能包含符号链接或特殊文件。")
            }
            requireQuota(uint(header, 24) <= MAX_FILE_BYTES, "单个文件不能超过 64 MiB。")
            val localOffset = uint(header, 42)
            val nameLength = ushort(header, 28)
            val skip = nameLength + ushort(header, 30) + ushort(header, 32)
            if (ushort(header, 34) != 0 || nameLength == 0 || localOffset >= offset || input.filePointer + skip > endOffset) {
                throw GameModException("invalid_archive", "ZIP 条目目录无效。")
            }
            val name = ByteArray(nameLength)
            input.readFully(name)
            val nextEntry = input.filePointer + skip - nameLength
            // ZipFile trusts the central compressed size even when the inflater finishes
            // earlier. Anchor that size to real, non-overlapping bytes before applying
            // compression-ratio limits or handing any entry to its inflater.
            if (localOffset + 30 > offset) throw GameModException("invalid_archive", "ZIP 本地条目被截断。")
            input.seek(localOffset)
            val local = ByteArray(30)
            input.readFully(local)
            val localNameLength = ushort(local, 26)
            val dataStart = localOffset + 30 + localNameLength + ushort(local, 28)
            val dataEnd = dataStart + uint(header, 20)
            if (uint(local, 0) != 0x04034b50L || ushort(local, 6) != flags ||
                ushort(local, 8) != method || localNameLength != nameLength ||
                dataStart > offset || dataEnd > offset
            ) throw GameModException("invalid_archive", "ZIP 本地条目与目录不符。")
            val localName = ByteArray(localNameLength)
            input.readFully(localName)
            if (!localName.contentEquals(name)) throw GameModException("invalid_archive", "ZIP 本地文件名与目录不符。")
            localRanges.add(localOffset to dataEnd)
            input.seek(nextEntry)
        }
        if (input.filePointer != endOffset) throw GameModException("invalid_archive", "ZIP 目录长度错误。")
        val orderedRanges = localRanges.sortedBy { it.first }
        for (index in 1 until orderedRanges.size) {
            if (orderedRanges[index].first < orderedRanges[index - 1].second) {
                throw GameModException("invalid_archive", "ZIP 本地条目相互重叠。")
            }
        }
        count
    }

    private fun normalizePath(name: String): String {
        val normalized = name.replace('\\', '/')
        if (normalized.startsWith('/') || normalized.length > 4096 || normalized.any {
                it.code < 32 || it == ':' || it == '%' || it == '?' || it == '#'
            }) throw GameModException("unsafe_path", "ZIP 包含不安全的文件路径。")
        val parts = normalized.split('/').filter { it.isNotEmpty() }
        if (parts.any { it == "." || it == ".." || it.length > 255 }) {
            throw GameModException("unsafe_path", "ZIP 包含不安全的相对路径。")
        }
        val path = (if (parts.firstOrNull() == "cache") parts.drop(1) else parts).joinToString("/")
        return path.replace(Regex("\\.hack\\.([A-Za-z0-9]+)$"), ".$1")
    }

    private fun classify(path: String, relativeFile: String): ArchiveResource {
        val ship = SHIP_PATH.matchEntire(path)
        val coordinate = isCoordinate(path)
        val kind: String
        val reason: String?
        val groupId: String?
        when {
            coordinate -> { kind = "coordinates"; reason = "coordinates_unsupported"; groupId = null }
            AUDIO_PATH.matches(path) -> { kind = "audio"; reason = null; groupId = null }
            path.startsWith("kcs/sound/") && (path.endsWith(".mp3", true) || path.endsWith(".wav", true)) -> { kind = "audio"; reason = "audio_filename_unsupported"; groupId = null }
            path.endsWith(".mp3", true) || path.endsWith(".wav", true) -> { kind = "audio"; reason = "audio_path_unsupported"; groupId = null }
            path.endsWith(".js", true) -> { kind = "unsupported"; reason = "script_unsupported"; groupId = null }
            path.endsWith(".json", true) -> { kind = "unsupported"; reason = "json_unsupported"; groupId = null }
            ship != null && ship.groupValues[1] in SHIP_TYPES -> {
                kind = "ship"; reason = null; groupId = "ship:${ship.groupValues[2]}"
            }
            path.startsWith("kcs2/img/") && path.endsWith(".png") -> { kind = "image"; reason = null; groupId = null }
            path.startsWith("kcs2/resources/ship/") -> { kind = "unsupported"; reason = "unknown_ship_asset"; groupId = null }
            path.startsWith("kcs/") || path.startsWith("kcs2/") -> { kind = "unsupported"; reason = "unsupported_type"; groupId = null }
            else -> { kind = "unsupported"; reason = "unsupported_path"; groupId = null }
        }
        val label = if (kind == "ship") "${ship!!.groupValues[2]} · ${ship.groupValues[1]}" else path
        return ArchiveResource(path, kind, label, reason == null, reason, groupId, relativeFile)
    }

    private fun applyDependencies(resources: List<ArchiveResource>, directory: File): Pair<List<ArchiveResource>, List<String>> {
        val warnings = linkedSetOf<String>()
        val paths = resources.mapTo(mutableSetOf()) { it.path }
        val ships = resources.filter { it.kind == "ship" }
        var unknownCoordinates = false
        val logical = resources.filterNot { it.kind == "coordinates" }.toMutableList()
        val bound = linkedMapOf<String, MutableList<Pair<ArchiveResource, GameModCoordinateData>>>()
        resources.filter { it.kind == "coordinates" }.groupBy { coordinate ->
            coordinate.path.substringAfterLast('/').replace(COORDINATE_SUFFIX, "")
        }.forEach { (stem, formats) ->
            val parsed = formats.map { coordinate -> coordinate to GameModCoordinateParser.parse(
                File(directory, coordinate.relativeFile), coordinate.path.substringAfterLast('.')) }
            val merged = GameModCoordinateParser.merge(parsed.map { it.second })
            if (merged.metadataIgnored) warnings.add("coordinate_metadata_ignored")
            if (merged.unknownFields) warnings.add("coordinate_unknown_fields_ignored")
            val matched = ships.filter { ship ->
                val imageStem = ship.path.substringAfterLast('/').removeSuffix(".png")
                stem.isNotEmpty() && stem != "config" && (imageStem == stem || imageStem.endsWith("_$stem") || ship.groupId == "ship:$stem")
            }.mapNotNull { it.groupId }.distinct()
            if (matched.size != 1) {
                unknownCoordinates = true
                val ordinal = formats.first().relativeFile.substringAfterLast('/').substringBefore('.')
                logical.add(formats.first().copy(path = "coordinates/unmatched/$ordinal", supported = false,
                    reason = "coordinate_unmatched", sourcePaths = formats.flatMap { it.sourcePaths }.distinct()))
            } else {
                val shipId = matched.single().substringAfter(':').toIntOrNull()?.toString()
                    ?: throw GameModException("invalid_coordinates", "Cannot bind coordinate metadata to a ship")
                bound.getOrPut(shipId) { mutableListOf() }.addAll(parsed)
            }
        }
        bound.forEach { (shipId, formats) ->
            val merged = GameModCoordinateParser.merge(formats.map { it.second })
            val filename = formats.first().first.relativeFile
            logical.add(ArchiveResource("coordinates/ship/$shipId", "coordinates", shipId.padStart(4, '0'), true, null,
                "ship:${shipId.padStart(4, '0')}", filename, formats.flatMap { it.first.sourcePaths }.distinct(), shipId, merged.graph))
        }
        if (unknownCoordinates) warnings.add("coordinate_dependency_unresolved")
        val checked = logical.map { resource ->
            when {
                resource.kind == "ship" && unknownCoordinates ->
                    resource.copy(supported = false, reason = "coordinate_dependency_unresolved")
                resource.supported && resource.path.endsWith(".png") &&
                    (resource.path.removeSuffix(".png") + ".json" in paths || resource.path + ".json" in paths) -> {
                    warnings.add("spritesheet_json_unsupported")
                    resource.copy(supported = false, reason = "spritesheet_json_dependency")
                }
                else -> resource
            }
        }
        if (resources.any { it.kind == "audio" && !it.supported }) warnings.add("unsupported_audio_files")
        if (checked.any { !it.supported && it.kind == "unsupported" }) warnings.add("unsupported_files")
        return checked to warnings.toList()
    }

    private fun isCoordinate(path: String): Boolean {
        val name = path.substringAfterLast('/').lowercase()
        return name == "config.ini" || name == "config.json" || name.endsWith(".config.ini") || name.endsWith(".config.json")
    }

    /** Validate chunk CRCs and inflate every scanline, without Android Bitmap or unbounded pixel allocation. */
    private fun requireQuota(valid: Boolean, message: String) {
        if (!valid) throw GameModException("quota_exceeded", message)
    }

    private fun ushort(bytes: ByteArray, offset: Int) = (bytes[offset].toInt() and 255) or ((bytes[offset + 1].toInt() and 255) shl 8)
    private fun uint(bytes: ByteArray, offset: Int) = (0..3).fold(0L) { value, index ->
        value or ((bytes[offset + index].toLong() and 255) shl (index * 8))
    }

    private companion object {
        const val MAX_ARCHIVE_BYTES = 256L * 1024 * 1024
        const val MAX_EXPANDED_BYTES = 1024L * 1024 * 1024
        const val MAX_FILE_BYTES = 64L * 1024 * 1024
        const val MAX_ENTRIES = 20_000
        const val MAX_RATIO = 200L
        val SHIP_PATH = Regex("kcs2/resources/ship/([a-z0-9_]+)/([0-9]{4})(?:_d)?_[A-Za-z0-9]+(?:_[A-Za-z0-9]+)?\\.png")
        val AUDIO_PATH = Regex("kcs/sound/kc[a-z0-9]+/[0-9]+\\.mp3")
        val WAV_PATH = Regex("kcs/sound/kc[a-z0-9]+/[0-9]+\\.(?i:wav)")
        val BAT_PATH = Regex("(?:ship(?:_[^/]+)?/)?[0-9]{4}(?:_[^/]+)?/[^/]+\\.(?:png|ini|json)")
        val COORDINATE_SUFFIX = Regex("(?:^config|\\.config)?\\.(?:ini|json)$", RegexOption.IGNORE_CASE)
        val SHIP_TYPES = setOf(
            "full", "full_dmg", "full_x2", "full_x2_dmg", "card", "card_dmg", "card_round", "banner", "banner_dmg", "banner_g_dmg",
            "banner2", "banner2_dmg", "banner2_g_dmg", "banner3", "banner3_g_dmg", "supply_character", "supply_character_dmg",
            "power_up", "power_up_dmg", "character_full", "character_full_dmg", "character_up", "character_up_dmg", "remodel", "remodel_dmg",
            "special", "album_status", "icon_box", "reward_card", "reward_icon", "text_class", "text_name", "text_remodel_mes",
        )
    }
}
