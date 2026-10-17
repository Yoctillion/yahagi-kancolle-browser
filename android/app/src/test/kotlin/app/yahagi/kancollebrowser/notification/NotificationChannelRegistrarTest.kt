package app.yahagi.kancollebrowser.notification

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class NotificationChannelRegistrarTest {
    @Test
    fun firstAccessRegistersWithoutAnActivityOrSnapshotUpdate() {
        val registrar = NotificationChannelRegistrar()
        var registrations = 0

        registrar.ensureRegistered("app.yahagi", "ja", 1) { registrations++ }

        assertEquals(1, registrations)
    }

    @Test
    fun repeatedAccessSkipsSuccessfulRegistration() {
        val registrar = NotificationChannelRegistrar()
        var registrations = 0

        repeat(10) {
            registrar.ensureRegistered("app.yahagi", "ja", 1) { registrations++ }
        }

        assertEquals(1, registrations)
    }

    @Test
    fun changingLocaleIncludingReturningToAnEarlierLocaleRegistersAgain() {
        val registrar = NotificationChannelRegistrar()
        val registeredLocales = mutableListOf<String>()

        listOf("zh", "zh", "ja", "ja", "zh", "zh").forEach { locale ->
            registrar.ensureRegistered("app.yahagi", locale, 1) { registeredLocales += locale }
        }

        assertEquals(listOf("zh", "ja", "zh"), registeredLocales)
    }

    @Test
    fun changingChannelSchemaRegistersAgain() {
        val registrar = NotificationChannelRegistrar()
        val registeredSchemas = mutableListOf<Int>()

        listOf(1, 1, 2, 2).forEach { schema ->
            registrar.ensureRegistered("app.yahagi", "ja", schema) { registeredSchemas += schema }
        }

        assertEquals(listOf(1, 2), registeredSchemas)
    }

    @Test
    fun anotherApplicationDoesNotReuseACompletedRegistration() {
        val registrar = NotificationChannelRegistrar()
        val registeredPackages = mutableListOf<String>()

        listOf("app.yahagi", "app.yahagi", "app.other", "app.other").forEach { packageName ->
            registrar.ensureRegistered(packageName, "ja", 1) { registeredPackages += packageName }
        }

        assertEquals(listOf("app.yahagi", "app.other"), registeredPackages)
    }

    @Test
    fun failedRegistrationIsRetriedThenCachedOnlyAfterSuccess() {
        val registrar = NotificationChannelRegistrar()
        var attempts = 0

        assertThrows(IllegalStateException::class.java) {
            registrar.ensureRegistered("app.yahagi", "ja", 1) {
                attempts++
                error("Channel service failed after a partial registration")
            }
        }
        repeat(2) {
            registrar.ensureRegistered("app.yahagi", "ja", 1) { attempts++ }
        }

        assertEquals(2, attempts)
    }

    @Test
    fun partialFailureOnLocaleChangeInvalidatesThePreviousLocale() {
        val registrar = NotificationChannelRegistrar()
        val registeredLocales = mutableListOf<String>()

        registrar.ensureRegistered("app.yahagi", "zh", 1) { registeredLocales += "zh" }
        assertThrows(IllegalStateException::class.java) {
            registrar.ensureRegistered("app.yahagi", "ja", 1) {
                registeredLocales += "partial-ja"
                error("Only some channel names changed")
            }
        }
        repeat(2) {
            registrar.ensureRegistered("app.yahagi", "zh", 1) { registeredLocales += "zh" }
        }

        assertEquals(listOf("zh", "partial-ja", "zh"), registeredLocales)
    }

    @Test
    fun aNewProcessRegistrarInitializesEvenAfterAnEarlierInstanceSucceeded() {
        var registrations = 0

        repeat(2) {
            val registrar = NotificationChannelRegistrar()
            repeat(2) {
                registrar.ensureRegistered("app.yahagi", "ja", 1) { registrations++ }
            }
        }

        assertEquals(2, registrations)
    }

    @Test
    fun concurrentFirstAccessCompletesOneRegistration() {
        val registrar = NotificationChannelRegistrar()
        val registrations = AtomicInteger()
        val ready = CountDownLatch(8)
        val start = CountDownLatch(1)
        val registrationStarted = CountDownLatch(1)
        val finishRegistration = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(8)
        try {
            val calls = List(8) {
                executor.submit {
                    ready.countDown()
                    check(start.await(5, TimeUnit.SECONDS))
                    registrar.ensureRegistered("app.yahagi", "ja", 1) {
                        registrations.incrementAndGet()
                        registrationStarted.countDown()
                        check(finishRegistration.await(5, TimeUnit.SECONDS))
                    }
                }
            }
            assertTrue(ready.await(5, TimeUnit.SECONDS))
            start.countDown()
            assertTrue(registrationStarted.await(5, TimeUnit.SECONDS))
            finishRegistration.countDown()
            calls.forEach { it.get(5, TimeUnit.SECONDS) }

            assertEquals(1, registrations.get())
        } finally {
            start.countDown()
            finishRegistration.countDown()
            executor.shutdownNow()
        }
    }
}
