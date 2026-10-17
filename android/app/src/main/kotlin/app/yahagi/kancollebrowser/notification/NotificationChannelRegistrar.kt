package app.yahagi.kancollebrowser.notification

internal class NotificationChannelRegistrar {
    private data class Registration(val packageName: String, val localeCode: String, val schemaVersion: Int)

    private var completedRegistration: Registration? = null

    @Synchronized
    fun ensureRegistered(
        packageName: String,
        localeCode: String,
        schemaVersion: Int,
        register: () -> Unit,
    ) {
        val requested = Registration(packageName, localeCode, schemaVersion)
        if (completedRegistration == requested) return

        // A failed refresh may already have changed some channels, so the old
        // locale is no longer safe to reuse either. Retry on the next access.
        completedRegistration = null
        register()
        completedRegistration = requested
    }
}
