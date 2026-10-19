package app.yahagi.kancollebrowser.mods

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
import java.io.InputStream
import java.io.OutputStream

/** SAF-backed user documents; never uses app-specific external storage. */
internal class GameModDocumentLibraryStore(
    private val resolver: ContentResolver,
    val treeUri: Uri,
    val rootDocumentId: String = DocumentsContract.getTreeDocumentId(treeUri),
) : GameModLibraryStore {
    private data class Document(val id: String, val name: String, val directory: Boolean, val size: Long, val modified: Long)
    private val directories = mutableMapOf("" to rootDocumentId)
    override val displayName: String get() = rootDocumentId.substringAfter(':', rootDocumentId)
    override val identity: String get() = GameModLibraryDirectoryPolicy.libraryIdentity(treeUri.authority.orEmpty(), rootDocumentId)
    val rootUri: Uri get() = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootDocumentId)

    init {
        GameModLibraryDirectoryPolicy.selectDocumentId(treeUri.authority.orEmpty(), rootDocumentId)
            .takeIf { it == rootDocumentId }
            ?: throw GameModException("library_directory_required", "Use a dedicated mod library below Documents")
        val selected = DocumentsContract.getTreeDocumentId(treeUri)
        requireWithin(selected, rootDocumentId)
    }

    override fun list(relative: String): List<GameModLibraryEntry> {
        checkPath(relative, true)
        return children(resolve(relative, directory = true)).map { GameModLibraryEntry(it.name, it.directory, it.size, it.modified) }
    }

    override fun openRead(relative: String): InputStream {
        checkPath(relative)
        return resolver.openInputStream(uri(resolve(relative)))
            ?: throw GameModException("library_unavailable", "Cannot read a library file")
    }

    override fun openWrite(relative: String): OutputStream {
        checkPath(relative)
        val parent = relative.substringBeforeLast('/', "")
        createDirectory(parent)
        val parentId = resolve(parent, directory = true)
        val name = relative.substringAfterLast('/')
        val existing = children(parentId).singleOrNull { it.name == name }
        if (existing?.directory == true) throw GameModException("library_write_failed", "A directory has the requested file name")
        val target = existing?.let { uri(it.id) } ?: DocumentsContract.createDocument(resolver, uri(parentId), mime(name), name)
            ?: throw GameModException("library_write_failed", "Cannot create a library file")
        requireWithin(rootDocumentId, DocumentsContract.getDocumentId(target))
        return resolver.openOutputStream(target, "wt")
            ?: throw GameModException("library_write_failed", "Cannot write a library file")
    }

    override fun createDirectory(relative: String) {
        checkPath(relative, true)
        var parentId = rootDocumentId
        var prefix = ""
        for (name in relative.split('/').filter(String::isNotEmpty)) {
            prefix = if (prefix.isEmpty()) name else "$prefix/$name"
            val existing = children(parentId).singleOrNull { it.name == name }
            if (existing != null) {
                if (!existing.directory) throw GameModException("library_write_failed", "A file blocks the library directory")
                parentId = existing.id
            } else {
                val created = DocumentsContract.createDocument(resolver, uri(parentId), DocumentsContract.Document.MIME_TYPE_DIR, name)
                    ?: throw GameModException("library_write_failed", "Cannot create a library directory")
                parentId = DocumentsContract.getDocumentId(created)
                requireWithin(rootDocumentId, parentId)
            }
            directories[prefix] = parentId
        }
    }

    override fun delete(relative: String): Boolean {
        checkPath(relative)
        val parent = relative.substringBeforeLast('/', "")
        val name = relative.substringAfterLast('/')
        return try {
            val target = children(resolve(parent, directory = true)).singleOrNull { it.name == name } ?: return true
            val result = DocumentsContract.deleteDocument(resolver, uri(target.id))
            directories.clear(); directories[""] = rootDocumentId
            result
        } catch (_: Exception) { false }
    }

    override fun rename(from: String, to: String): Boolean {
        checkPath(from); checkPath(to)
        if (from.substringBeforeLast('/', "") != to.substringBeforeLast('/', "")) return false
        return try {
            val parent = resolve(from.substringBeforeLast('/', ""), directory = true)
            val entries = children(parent)
            if (entries.any { it.name == to.substringAfterLast('/') }) return false
            val source = entries.singleOrNull { it.name == from.substringAfterLast('/') } ?: return false
            val renamed = DocumentsContract.renameDocument(resolver, uri(source.id), to.substringAfterLast('/')) ?: return false
            requireWithin(rootDocumentId, DocumentsContract.getDocumentId(renamed))
            directories.clear(); directories[""] = rootDocumentId
            true
        } catch (_: Exception) { false }
    }

    private fun resolve(relative: String, directory: Boolean = false): String {
        var parentId = rootDocumentId
        var prefix = ""
        val parts = relative.split('/').filter(String::isNotEmpty)
        parts.forEachIndexed { index, name ->
            val child = children(parentId).singleOrNull { it.name == name }
                ?: throw GameModException("library_source_missing", "A library file or directory is missing")
            if ((index < parts.lastIndex || directory) && !child.directory) throw GameModException("library_unavailable", "A library directory is not readable")
            parentId = child.id
            prefix = if (prefix.isEmpty()) name else "$prefix/$name"
            if (child.directory) directories[prefix] = parentId
        }
        return parentId
    }

    private fun children(parent: String): List<Document> {
        requireWithin(rootDocumentId, parent)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parent)
        val result = mutableListOf<Document>()
        resolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED), null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getString(0); val name = cursor.getString(1)
                requireWithin(rootDocumentId, id)
                checkPath(name)
                result.add(Document(id, name, cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR,
                    if (cursor.isNull(3)) 0 else cursor.getLong(3), if (cursor.isNull(4)) 0 else cursor.getLong(4)))
            }
        } ?: throw GameModException("library_unavailable", "The selected library is not available")
        return result
    }

    private fun checkPath(relative: String, allowRoot: Boolean = false) = GameModLibraryDirectoryPolicy.relativePath(relative, allowRoot)
    private fun uri(id: String): Uri { requireWithin(rootDocumentId, id); return DocumentsContract.buildDocumentUriUsingTree(treeUri, id) }
    private fun requireWithin(parent: String, candidate: String) {
        if (candidate != parent && !candidate.startsWith("$parent/")) throw GameModException("unsafe_path", "Document escaped the selected mod library")
    }
    private fun mime(name: String) = when (name.substringAfterLast('.').lowercase()) {
        "json" -> "application/json"; "png" -> "image/png"; "mp3" -> "audio/mpeg"; "wav" -> "audio/wav"; "zip" -> "application/zip"; else -> "application/octet-stream"
    }

    companion object {
        fun documentExists(resolver: ContentResolver, treeUri: Uri, documentId: String): Boolean {
            val granted = DocumentsContract.getTreeDocumentId(treeUri)
            if (documentId != granted && !documentId.startsWith("$granted/")) throw GameModException("unsafe_path", "Document escaped its grant")
            if (documentId == granted) return resolver.query(DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId),
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)?.use { it.moveToFirst() } ?: false
            var parent = granted
            for (name in documentId.removePrefix("$granted/").split('/')) {
                var found: String? = null
                resolver.query(DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parent),
                    arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                    null, null, null)?.use { cursor ->
                    while (cursor.moveToNext()) if (cursor.getString(1) == name) found = cursor.getString(0)
                } ?: throw GameModException("library_unavailable", "Cannot inspect the default folder")
                parent = found ?: return false
                if (!parent.startsWith("$granted/")) throw GameModException("unsafe_path", "Document escaped its grant")
            }
            return true
        }

        fun renameRoot(resolver: ContentResolver, treeUri: Uri, documentId: String, name: String): String? {
            GameModLibraryDirectoryPolicy.relativePath(name, false)
            if ('/' in name) throw GameModException("unsafe_path", "A directory name cannot contain separators")
            val granted = DocumentsContract.getTreeDocumentId(treeUri)
            val parent = documentId.substringBeforeLast('/', "")
            if (parent.isEmpty() || (parent != granted && !parent.startsWith("$granted/"))) {
                throw GameModException("library_default_migration_permission", "Authorize Documents before renaming the default folder")
            }
            resolver.query(DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parent),
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) if (cursor.getString(0) == name) {
                    throw GameModException("library_default_migration_conflict", "The destination already exists")
                }
            } ?: throw GameModException("library_unavailable", "Cannot read the default folder's parent")
            return DocumentsContract.renameDocument(resolver, DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId), name)
                ?.let(DocumentsContract::getDocumentId)
        }

        fun selected(resolver: ContentResolver, treeUri: Uri): GameModDocumentLibraryStore {
            val original = DocumentsContract.getTreeDocumentId(treeUri)
            val target = GameModLibraryDirectoryPolicy.selectDocumentId(treeUri.authority.orEmpty(), original)
            // Selecting Documents creates a dedicated child without scanning other documents.
            if (target == original) return GameModDocumentLibraryStore(resolver, treeUri)
            // Give the manager a chance to sync and rename an existing legacy default.
            // Creating Mods first would turn a safe rename into a destination conflict.
            val legacy = target.substringBeforeLast('/') + "/魔改"
            if (documentExists(resolver, treeUri, legacy)) return GameModDocumentLibraryStore(resolver, treeUri, legacy)
            var parentId = original
            for (name in target.removePrefix("$original/").split('/')) {
                val parent = DocumentsContract.buildDocumentUriUsingTree(treeUri, parentId)
                val childUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
                var found: String? = null
                resolver.query(childUri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use { cursor ->
                    while (cursor.moveToNext()) if (cursor.getString(1) == name) {
                        if (cursor.getString(2) != DocumentsContract.Document.MIME_TYPE_DIR) throw GameModException("library_write_failed", "A file blocks the mod library")
                        found = cursor.getString(0)
                    }
                } ?: throw GameModException("library_unavailable", "Cannot read Documents")
                parentId = found ?: DocumentsContract.createDocument(resolver, parent, DocumentsContract.Document.MIME_TYPE_DIR, name)
                    ?.let(DocumentsContract::getDocumentId) ?: throw GameModException("library_write_failed", "Cannot create the mod library")
                if (!parentId.startsWith("$original/")) throw GameModException("unsafe_path", "Library escaped Documents")
            }
            return GameModDocumentLibraryStore(resolver, treeUri, parentId)
        }
    }
}
