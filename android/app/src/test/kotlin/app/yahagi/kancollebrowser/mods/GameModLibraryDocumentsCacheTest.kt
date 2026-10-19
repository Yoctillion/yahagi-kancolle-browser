package app.yahagi.kancollebrowser.mods

import org.junit.Assert.*
import org.junit.Test

/** Exercises the same path and URI cache used by SAF, without Android or a device. */
class GameModLibraryDocumentsCacheTest {
    @Test fun `fifty packages reuse each directory query and document URI within a content pass`() {
        val provider = Provider()
        repeat(50) { pack ->
            repeat(20) { file -> provider.file("pack-$pack/kcs2/resources/ship/full/$file.png", "image-$file") }
        }
        val sessions = provider.sessions()
        val expected = provider.paths().filter { it.endsWith(".png") }.sorted()

        val actual = sessions.withReadSession {
            walk(sessions, "").also { paths ->
                repeat(2) {
                    paths.forEach { path -> assertEquals(provider.read(path), provider.readUri(sessions.resolveUri(path))) }
                }
            }
        }

        assertEquals(expected, actual.sorted())
        assertEquals("Each listed directory should be queried once", 1 + 50 * 5, provider.queries.values.sum())
        assertTrue(provider.queries.values.all { it == 1 })
        assertEquals("Every file URI should be built once despite repeated reads", 1_000, provider.uriBuilds.values.sum())
    }

    @Test fun `copy and verification sessions see a file added between passes`() {
        val provider = Provider().apply { file("ship/full/old.png", "first") }
        val sessions = provider.sessions()
        val copied = sessions.withReadSession { walk(sessions, "ship") }
        provider.file("ship/full/new.png", "new")
        val verified = sessions.withReadSession { walk(sessions, "ship") }

        assertEquals(listOf("ship/full/old.png"), copied)
        assertEquals(setOf("ship/full/old.png", "ship/full/new.png"), verified.toSet())
        assertEquals(2, provider.queries.getValue(provider.id("ship/full")))
    }

    @Test fun `a later session refreshes external directory rename deletion and edited metadata`() {
        val provider = Provider().apply {
            file("ship/full/old.png", "old")
            file("ship/full/deleted.png", "gone")
        }
        val sessions = provider.sessions()
        sessions.withReadSession { walk(sessions, "").forEach { sessions.resolveUri(it) } }
        provider.rename("ship", "renamed")
        provider.remove("renamed/full/deleted.png")
        provider.file("renamed/full/old.png", "edited with a new size")

        sessions.withReadSession {
            assertEquals(listOf("renamed"), sessions.list("").map { it.name })
            val entry = sessions.list("renamed/full").single()
            assertEquals("old.png", entry.name)
            assertEquals("edited with a new size".length.toLong(), entry.size)
            assertEquals("edited with a new size", provider.readUri(sessions.resolveUri("renamed/full/old.png")))
            expectCode("library_source_missing") { sessions.resolveUri("ship/full/old.png") }
        }
    }

    @Test fun `calls outside a session always refresh external changes`() {
        val provider = Provider().apply { file("ship/old.txt", "old") }
        val sessions = provider.sessions()
        assertEquals(listOf("old.txt"), sessions.list("ship").map { it.name })
        provider.rename("ship/old.txt", "ship/new.txt")
        assertEquals(listOf("new.txt"), sessions.list("ship").map { it.name })
        assertEquals("old", provider.readUri(sessions.resolveUri("ship/new.txt")))
        provider.remove("ship/new.txt")
        expectCode("library_source_missing") { sessions.resolveUri("ship/new.txt") }
    }

    @Test fun `mutation invalidation refreshes an active session including renamed document URIs`() {
        val provider = Provider().apply { file("ship/old.txt", "old") }
        val sessions = provider.sessions()
        sessions.withReadSession {
            val oldUri = sessions.resolveUri("ship/old.txt")
            provider.rename("ship", "renamed")
            sessions.invalidate()
            assertEquals("old", provider.readUri(sessions.resolveUri("renamed/old.txt")))
            expectCode("library_source_missing") { sessions.resolveUri("ship/old.txt") }
            provider.remove("renamed/old.txt")
            sessions.invalidate()
            assertTrue(sessions.list("renamed").isEmpty())
            provider.file("renamed/new.txt", "new content")
            sessions.invalidate()
            assertEquals("new content", provider.readUri(sessions.resolveUri("renamed/new.txt")))
            assertNotEquals(oldUri, sessions.resolveUri("renamed/new.txt"))
        }
    }

    @Test fun `invalidation from another thread refreshes an active reader`() {
        val provider = Provider().apply { file("ship/old.txt", "old") }
        val sessions = provider.sessions()
        sessions.withReadSession {
            assertEquals(listOf("old.txt"), sessions.list("ship").map { it.name })
            Thread {
                provider.rename("ship/old.txt", "ship/new.txt")
                sessions.invalidate()
            }.apply { start(); join() }
            assertEquals(listOf("new.txt"), sessions.list("ship").map { it.name })
        }
    }

    @Test fun `failed session releases snapshots and URIs before the next call`() {
        val provider = Provider().apply { file("ship/old.txt", "old") }
        val sessions = provider.sessions()
        val failure = IllegalStateException("abort pass")
        assertSame(failure, runCatching {
            sessions.withReadSession {
                sessions.resolveUri("ship/old.txt")
                throw failure
            }
        }.exceptionOrNull())
        provider.rename("ship/old.txt", "ship/new.txt")
        assertEquals("old", provider.readUri(sessions.resolveUri("ship/new.txt")))
        expectCode("library_source_missing") { sessions.resolveUri("ship/old.txt") }
    }

    @Test fun `nested content sessions refresh independently and discard the earlier outer view`() {
        val provider = Provider().apply { file("ship/old.txt", "old") }
        val sessions = provider.sessions()
        sessions.withReadSession {
            assertEquals(listOf("old.txt"), sessions.list("ship").map { it.name })
            provider.rename("ship/old.txt", "ship/new.txt")
            sessions.withReadSession {
                assertEquals(listOf("new.txt"), sessions.list("ship").map { it.name })
            }
            assertEquals(listOf("new.txt"), sessions.list("ship").map { it.name })
        }
    }

    @Test fun `URI objects are shared only within their session`() {
        val provider = Provider().apply { file("ship/file.txt", "data") }
        val sessions = provider.sessions()
        lateinit var first: FakeUri
        sessions.withReadSession {
            first = sessions.resolveUri("ship/file.txt")
            assertSame(first, sessions.resolveUri("ship/file.txt"))
        }
        sessions.withReadSession { assertNotSame(first, sessions.resolveUri("ship/file.txt")) }
        assertEquals(2, provider.uriBuilds.getValue(provider.id("ship/file.txt")))
    }

    @Test fun `cached paths retain directory and traversal checks`() {
        val provider = Provider().apply { file("ship/file.txt", "data") }
        val sessions = provider.sessions()
        sessions.withReadSession {
            sessions.list("ship")
            sessions.resolveUri("ship/file.txt")
            expectCode("library_unavailable") { sessions.list("ship/file.txt") }
            expectCode("library_unavailable") { sessions.resolveUri("ship/file.txt/child") }
            expectCode("unsafe_path") { sessions.resolveUri("ship/../outside") }
        }
    }

    @Test fun `a failed provider query is not cached as an empty directory`() {
        val provider = Provider().apply { file("ship/file.txt", "data") }
        val sessions = provider.sessions()
        sessions.withReadSession {
            provider.failNextQuery = true
            expectCode("library_unavailable") { sessions.list("") }
            assertEquals(listOf("ship"), sessions.list("").map { it.name })
        }
        assertEquals(2, provider.queries.getValue(provider.id("")))
    }

    @Test fun `ambiguous provider names never become resolved paths`() {
        val sessions = GameModLibraryReadSessions("root", { _ -> listOf(
            GameModLibraryDocument("root/one", "same.txt", false, 0, 0),
            GameModLibraryDocument("root/two", "same.txt", false, 0, 0),
        ) }, ::FakeUri)
        sessions.withReadSession {
            assertEquals(2, sessions.list("").size)
            expectCode("library_source_missing") { sessions.resolveUri("same.txt") }
        }
    }

    @Test fun `a provider display name with separators cannot bypass ancestor resolution`() {
        val sessions = GameModLibraryReadSessions("root", { _ -> listOf(
            GameModLibraryDocument("root/file-id", "folder/file.txt", false, 0, 0),
        ) }, ::FakeUri)
        sessions.withReadSession {
            sessions.list("")
            expectCode("library_source_missing") { sessions.resolveUri("folder/file.txt") }
        }
    }

    private fun walk(sessions: GameModLibraryReadSessions<FakeUri>, parent: String): List<String> =
        sessions.list(parent).flatMap { child ->
            val path = if (parent.isEmpty()) child.name else "$parent/${child.name}"
            if (child.directory) walk(sessions, path) else listOf(path)
        }

    private fun expectCode(code: String, block: () -> Any?) {
        assertEquals(code, (runCatching(block).exceptionOrNull() as? GameModException)?.code)
    }

    private class FakeUri(val documentId: String)

    private class Provider {
        private val root = "primary:Documents/Mods"
        private val documents = linkedMapOf<String, GameModLibraryDocument>()
        private val contents = mutableMapOf<String, String>()
        val queries = mutableMapOf<String, Int>()
        val uriBuilds = mutableMapOf<String, Int>()
        var failNextQuery = false

        fun id(path: String) = if (path.isEmpty()) root else "$root/$path"
        fun paths(): List<String> = documents.keys.toList()
        fun sessions() = GameModLibraryReadSessions(root, { parent ->
            queries[parent] = (queries[parent] ?: 0) + 1
            if (failNextQuery) {
                failNextQuery = false
                throw GameModException("library_unavailable", "Provider is temporarily unavailable")
            }
            documents.filterKeys { id(it.substringBeforeLast('/', "")) == parent }.values.toList()
        }, { documentId ->
            uriBuilds[documentId] = (uriBuilds[documentId] ?: 0) + 1
            FakeUri(documentId)
        })

        fun file(path: String, content: String) {
            val parts = path.split('/')
            for (index in 1 until parts.size) {
                val directory = parts.take(index).joinToString("/")
                documents[directory] = GameModLibraryDocument(id(directory), parts[index - 1], true, 0, 1)
            }
            documents[path] = GameModLibraryDocument(id(path), parts.last(), false, content.length.toLong(), 1)
            contents[path] = content
        }

        fun read(path: String): String = contents.getValue(path)
        fun readUri(uri: FakeUri): String = read(uri.documentId.removePrefix("$root/"))
        fun remove(path: String) {
            documents.keys.filter { it == path || it.startsWith("$path/") }.forEach {
                documents.remove(it); contents.remove(it)
            }
        }

        fun rename(from: String, to: String) {
            val entries = documents.filterKeys { it == from || it.startsWith("$from/") }
            val bytes = contents.filterKeys { it == from || it.startsWith("$from/") }
            remove(from)
            entries.forEach { (oldPath, document) ->
                val path = to + oldPath.removePrefix(from)
                documents[path] = document.copy(id = id(path), name = path.substringAfterLast('/'))
            }
            bytes.forEach { (oldPath, content) -> contents[to + oldPath.removePrefix(from)] = content }
        }
    }
}
