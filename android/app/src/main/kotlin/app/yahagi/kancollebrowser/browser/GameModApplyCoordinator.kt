package app.yahagi.kancollebrowser.browser

import java.util.concurrent.atomic.AtomicBoolean

/** Binds a resource snapshot only when the verified frame is about to receive reload. */
internal class GameModApplyCoordinator<T : Any>(
    private val applyConfig: () -> T,
    private val rollback: (T) -> Unit,
    private val finish: (T) -> Unit,
    private val requestReload: (() -> Unit, (String, Boolean) -> Unit) -> Unit,
) {
    private val running = AtomicBoolean(false)

    fun apply(gameOpen: Boolean, onComplete: (String) -> Unit) {
        if (!running.compareAndSet(false, true)) {
            onComplete("blocked")
            return
        }
        var token: T? = null
        val completed = AtomicBoolean(false)
        val complete: (String, Boolean) -> Unit = complete@{ result, dispatched ->
            if (!completed.compareAndSet(false, true)) return@complete
            var outcome = result
            try {
                token?.let { if (dispatched) finish(it) else rollback(it) }
            } catch (_: Exception) {
                outcome = "failed"
            } finally {
                running.set(false)
            }
            onComplete(outcome)
        }
        val prepare = {
            check(!completed.get() && token == null) { "Apply transaction is no longer active" }
            token = applyConfig()
        }
        try {
            if (gameOpen) requestReload(prepare, complete)
            else {
                prepare()
                complete("noGame", true)
            }
        } catch (_: Exception) {
            complete("failed", false)
        }
    }
}
