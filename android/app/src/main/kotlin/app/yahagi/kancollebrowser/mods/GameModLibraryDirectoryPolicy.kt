package app.yahagi.kancollebrowser.mods

/** Location checks shared by the picker and document operations. */
object GameModLibraryDirectoryPolicy {
    /** Stable across a broad Documents grant and a later grant to the library itself. */
    fun libraryIdentity(authority: String, rootDocumentId: String): String {
        if (selectDocumentId(authority, rootDocumentId) != rootDocumentId) {
            throw GameModException("library_directory_required", "Use a dedicated mod library below Documents")
        }
        // Keep the existing private synchronization journal key across the default rename.
        val stableRoot = if (rootDocumentId.substringAfter(':') == "Documents/Yahagi/Mods")
            rootDocumentId.substringBefore(':') + ":Documents/Yahagi/魔改" else rootDocumentId
        return "$authority:$stableRoot"
    }

    fun selectDocumentId(authority: String, documentId: String): String {
        val volume = documentId.substringBefore(':', "")
        val path = documentId.substringAfter(':', "")
        if (authority != "com.android.externalstorage.documents" || volume.isBlank() ||
            ':' in path || !(path == "Documents" || path.startsWith("Documents/"))) {
            throw GameModException("library_directory_required", "Choose a folder in this device's Documents directory")
        }
        relativePath(path, false)
        return if (path == "Documents") "$volume:Documents/Yahagi/Mods" else documentId
    }

    fun legacyDefaultTarget(authority: String, documentId: String): String? =
        if (authority == "com.android.externalstorage.documents" && documentId.substringBefore(':').isNotBlank() &&
            documentId.substringAfter(':', "") == "Documents/Yahagi/魔改")
            documentId.substringBefore(':') + ":Documents/Yahagi/Mods" else null

    fun relativePath(path: String, allowRoot: Boolean): String {
        if (path.isEmpty() && allowRoot) return path
        if (path.isEmpty() || path.startsWith('/') || '\\' in path || ':' in path ||
            path.any { it.code < 32 } || path.split('/').any { it.isEmpty() || it == "." || it == ".." }) {
            throw GameModException("unsafe_path", "The path must remain within the selected mod library")
        }
        return path
    }
}
