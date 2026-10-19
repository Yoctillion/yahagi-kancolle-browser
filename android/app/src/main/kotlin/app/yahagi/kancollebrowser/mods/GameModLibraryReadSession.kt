package app.yahagi.kancollebrowser.mods

internal data class GameModLibraryDocument(
    val id: String, val name: String, val directory: Boolean, val size: Long, val modified: Long,
)

/**
 * Reuses provider listings and document URIs for one content pass only. A second pass must
 * start a new session so additions, removals and provider-assigned IDs are queried again.
 */
internal class GameModLibraryReadSessions<U : Any>(
    private val rootDocumentId: String,
    private val queryChildren: (String) -> List<GameModLibraryDocument>,
    private val buildUri: (String) -> U,
) {
    private val active = ThreadLocal<Snapshot?>()
    @Volatile private var generation = 0L

    fun <T> withReadSession(block: () -> T): T {
        val previous = active.get()
        active.set(Snapshot(generation))
        try {
            return block()
        } finally {
            if (previous == null) active.remove() else {
                // A nested pass may have observed external changes; never revive its old view.
                previous.reset(generation)
                active.set(previous)
            }
        }
    }

    /** Also invalidates sessions on other threads when a store mutation finishes. */
    @Synchronized fun invalidate() { generation++ }

    fun list(relative: String): List<GameModLibraryDocument> {
        GameModLibraryDirectoryPolicy.relativePath(relative, true)
        val snapshot = snapshot()
        val listing = snapshot.children(snapshot.resolve(relative, directory = true).id)
        listing.uniqueNames.forEach { (name, document) ->
            if ('/' !in name) snapshot.resolved[if (relative.isEmpty()) name else "$relative/$name"] = document
        }
        return listing.entries
    }

    fun resolveUri(relative: String): U {
        GameModLibraryDirectoryPolicy.relativePath(relative, false)
        val snapshot = snapshot()
        return snapshot.uri(snapshot.resolve(relative, directory = false).id)
    }

    fun uri(documentId: String): U = snapshot().uri(documentId)

    fun resolve(relative: String, directory: Boolean = false): String {
        GameModLibraryDirectoryPolicy.relativePath(relative, true)
        return snapshot().resolve(relative, directory).id
    }

    private fun snapshot(): Snapshot {
        // Direct calls outside a content pass deliberately have no persistent cache.
        val snapshot = active.get() ?: return Snapshot(generation)
        if (snapshot.generation != generation) snapshot.reset(generation)
        return snapshot
    }

    private data class Listing(val entries: List<GameModLibraryDocument>) {
        val uniqueNames = entries.groupBy { it.name }.mapNotNull { (name, matches) ->
            matches.singleOrNull()?.let { name to it }
        }.toMap()
    }

    private inner class Snapshot(var generation: Long) {
        val resolved = mutableMapOf("" to GameModLibraryDocument(rootDocumentId, "", true, 0, 0))
        private val listings = mutableMapOf<String, Listing>()
        private val uris = mutableMapOf<String, U>()

        fun reset(nextGeneration: Long) {
            listings.clear(); uris.clear(); resolved.clear()
            resolved[""] = GameModLibraryDocument(rootDocumentId, "", true, 0, 0)
            generation = nextGeneration
        }

        fun children(parentId: String): Listing = listings.getOrPut(parentId) {
            Listing(queryChildren(parentId).toList())
        }

        fun uri(documentId: String): U = uris.getOrPut(documentId) { buildUri(documentId) }

        fun resolve(relative: String, directory: Boolean): GameModLibraryDocument {
            resolved[relative]?.let { return requireDirectory(it, directory) }
            var parent = resolved.getValue("")
            var prefix = ""
            val parts = relative.split('/').filter(String::isNotEmpty)
            parts.forEachIndexed { index, name ->
                prefix = if (prefix.isEmpty()) name else "$prefix/$name"
                val child = resolved[prefix] ?: children(parent.id).uniqueNames[name]
                    ?: throw GameModException("library_source_missing", "A library file or directory is missing")
                requireDirectory(child, index < parts.lastIndex || directory)
                resolved[prefix] = child
                parent = child
            }
            return parent
        }

        private fun requireDirectory(document: GameModLibraryDocument, required: Boolean): GameModLibraryDocument {
            if (required && !document.directory) {
                throw GameModException("library_unavailable", "A library directory is not readable")
            }
            return document
        }
    }
}
