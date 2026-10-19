package app.yahagi.kancollebrowser.mods

/** The receipt is private and durable before a provider rename can change document IDs. */
internal interface GameModDefaultMigrationAccess {
    fun exists(documentId: String): Boolean
    fun rename(documentId: String, name: String): String?
    fun recordIntent(targetId: String): Boolean
    fun saveRoot(targetId: String): Boolean
    fun clearIntent()
}

internal data class GameModDefaultMigrationResult(val rootDocumentId: String, val warning: String? = null)

internal object GameModLibraryDefaultMigration {
    fun migrate(authority: String, rootId: String, parentAuthorized: Boolean, pendingTarget: String?,
        access: GameModDefaultMigrationAccess): GameModDefaultMigrationResult {
        val target = GameModLibraryDirectoryPolicy.legacyDefaultTarget(authority, rootId)
            ?: return GameModDefaultMigrationResult(rootId)
        fun failure(root: String = rootId) = GameModDefaultMigrationResult(root, "library_default_migration_failed")
        if (!parentAuthorized) return GameModDefaultMigrationResult(rootId, "library_default_migration_permission")
        var moved: String? = null
        try {
            val oldExists = access.exists(rootId)
            val newExists = access.exists(target)
            if (oldExists && newExists) {
                if (pendingTarget != null) access.clearIntent()
                return GameModDefaultMigrationResult(rootId, "library_default_migration_conflict")
            }
            if (!oldExists) {
                if (!newExists || pendingTarget != target) return failure()
                return if (access.saveRoot(target)) GameModDefaultMigrationResult(target) else failure(target)
            }
            if (!access.recordIntent(target)) return failure()
            moved = access.rename(rootId, "Mods")
            if (moved == null) { access.clearIntent(); return failure() }
            if (moved == target && access.saveRoot(target)) return GameModDefaultMigrationResult(target)
            if (!access.exists(rootId) && access.rename(moved, "魔改") == rootId) {
                access.clearIntent(); return failure()
            }
            // Keep the receipt if rollback is unavailable so startup can recover this exact rename.
            return failure(if (moved == target) moved else rootId)
        } catch (_: SecurityException) {
            return GameModDefaultMigrationResult(moved ?: rootId, "library_default_migration_permission")
        } catch (_: Exception) { return failure(moved ?: rootId) }
    }
}
