package app.yahagi.kancollebrowser.backup

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Test

class BackupExportExecutorTest {
    @Test fun blockedProviderDoesNotQueueAnotherExportsStaging() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val next = CountDownLatch(1)
        BackupExportExecutor(timeoutMillis = 5_000, maxConcurrent = 2).use { executor ->
            try {
                executor.execute { entered.countDown(); release.await() }
                assertTrue(entered.await(2, TimeUnit.SECONDS))
                executor.execute { next.countDown() }
                assertTrue("Another export must not wait for the blocked provider", next.await(1, TimeUnit.SECONDS))
            } finally { release.countDown() }
        }
    }

    @Test fun timedOutIoRepliesOnceWhileItsRecoverableWriteMayFinishLater() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val failed = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val failure = AtomicReference<Throwable>()
        val failures = AtomicInteger()
        BackupExportExecutor(timeoutMillis = 100, maxConcurrent = 2).use { executor ->
            try {
                executor.execute(onFailure = {
                    failure.set(it); failures.incrementAndGet(); failed.countDown()
                }) {
                    entered.countDown()
                    release.await()
                    finished.countDown()
                    throw IllegalStateException("Provider returned a late error")
                }
                assertTrue(entered.await(2, TimeUnit.SECONDS))
                assertTrue("Provider I/O needs a bounded reply time", failed.await(1, TimeUnit.SECONDS))
                assertTrue(failure.get() is TimeoutException)
                release.countDown()
                assertTrue(finished.await(2, TimeUnit.SECONDS))
                assertEquals(1, failures.get())
            } finally { release.countDown() }
        }
    }

    @Test fun saturatedProvidersRejectNewWorkPromptlyInsteadOfGrowingThreadsOrAQueue() {
        val entered = CountDownLatch(2)
        val release = CountDownLatch(1)
        val rejected = CountDownLatch(1)
        val unexpected = AtomicInteger()
        BackupExportExecutor(timeoutMillis = 5_000, maxConcurrent = 2).use { executor ->
            try {
                repeat(2) { executor.execute { entered.countDown(); release.await() } }
                assertTrue(entered.await(1, TimeUnit.SECONDS))
                executor.execute(onFailure = { rejected.countDown() }) { unexpected.incrementAndGet() }
                assertTrue(rejected.await(1, TimeUnit.SECONDS))
                assertEquals(0, unexpected.get())
            } finally { release.countDown() }
        }
    }
}
