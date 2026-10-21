package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class GameModStateTargetTypeTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun `draft save rejects an empty directory at the state path without changing memory`() {
        val root = temporary.newFolder()
        val repository = GameModRepository(root)
        repository.saveDraft(config(master = false))
        val before = repository.status()
        val index = root.resolve("state.json")
        val durable = index.readBytes()
        assertTrue(index.delete())
        assertTrue(index.mkdir())
        try {
            val failure = runCatching { repository.saveDraft(config(master = true)) }.exceptionOrNull()
            assertEquals("storage_error", (failure as? GameModException)?.code)
            assertTrue("The obstructing directory must be preserved", index.isDirectory)
            assertEquals(before, repository.status())
            assertNoTemporaryStates(root)
        } finally {
            assertTrue(index.delete())
            index.writeBytes(durable)
        }
        repository.saveDraft(config(master = true))
        assertEquals(true, (GameModRepository(root).status()["draft"] as Map<*, *>)["master"])
    }

    @Test fun `prepared apply rejects a directory target and remains cancellable before retry`() {
        val root = temporary.newFolder()
        val repository = GameModRepository(root)
        repository.saveDraft(config(master = true))
        val before = repository.status()
        val portraits = repository.portraitSnapshot()
        val token = repository.prepareApply()
        val index = root.resolve("state.json")
        val durable = index.readBytes()
        assertTrue(index.delete())
        assertTrue(index.mkdir())
        try {
            val failure = runCatching { repository.publishApply(token) }.exceptionOrNull()
            assertEquals("storage_error", (failure as? GameModException)?.code)
            assertTrue("The obstructing directory must be preserved", index.isDirectory)
            assertEquals(before, repository.status())
            assertEquals(portraits, repository.portraitSnapshot())
        } finally {
            repository.cancelPreparedApply(token)
            assertTrue(index.delete())
            index.writeBytes(durable)
        }
        assertNoTemporaryStates(root)
        repository.finishApply(repository.applyDraft())
        assertEquals(true, (GameModRepository(root).status()["applied"] as Map<*, *>)["master"])
    }

    private fun config(master: Boolean) = mapOf(
        "master" to master,
        "order" to emptyList<String>(),
        "enabledPackages" to emptyList<String>(),
        "enabledResources" to emptyList<String>(),
    )

    private fun assertNoTemporaryStates(root: File) {
        assertFalse(root.listFiles()!!.any { it.name.startsWith("state-") && it.name.endsWith(".tmp") })
    }
}
