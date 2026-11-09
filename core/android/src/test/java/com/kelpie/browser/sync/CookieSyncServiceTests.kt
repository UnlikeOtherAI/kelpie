package com.kelpie.browser.sync

import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * Two (or three) sync services in one JVM over real loopback HTTP, with real
 * crypto and the real core-sync store, a fake UOA and in-memory cookie stores.
 */
class CookieSyncServiceTests {
    @get:Rule val folder = TemporaryFolder()

    private val uoa = FakeUOA()
    private val network = LoopbackDiscovery.Network()
    private val running = mutableListOf<CookieSyncService>()
    private val fast =
        SyncTimings(
            pageLoadQuietMs = 50,
            recentScanMs = 60_000,
            fullScanMs = 60_000,
            retryOpenMs = 500,
            warmupPeerWindowMs = 1_500,
            warmupMaxMs = 6_000,
            fallbackInitiateMs = 2_000,
        )

    private inner class Device(
        val name: String,
        val account: FakeUOA.Account,
        val cookies: MemoryCookies = MemoryCookies(),
        val directory: File = folder.newFolder(name),
    ) {
        var service = start(SyncLaunches())

        fun start(launches: SyncLaunches): CookieSyncService =
            CookieSyncService(
                account = account,
                cookies = cookies,
                directory = directory,
                discovery = LoopbackDiscovery(network),
                subnets = { emptyList() },
                transport = SyncHttpTransport(),
                deviceName = name,
                recent = RecentLoads(System::currentTimeMillis),
                launches = launches,
                timings = fast,
                log = SyncLog { _, message -> println("[$name] $message") },
            ).also {
                running.add(it)
                it.start()
            }

        /** Stops the service and comes back as a new process: session cookies are gone. */
        suspend fun restart() {
            service.stop()
            cookies.dropSessionCookies()
            service = start(SyncLaunches())
        }

        suspend fun changed() = service.scan()
    }

    @After fun stopAll() =
        runBlocking {
            running.forEach { it.stop() }
        }

    private suspend fun eventually(
        what: String,
        timeoutMs: Long = 30_000,
        check: suspend () -> Boolean,
    ) {
        try {
            withTimeout(timeoutMs) {
                while (!check()) delay(100)
            }
        } catch (error: kotlinx.coroutines.TimeoutCancellationException) {
            throw AssertionError("timed out waiting for: $what")
        }
    }

    private suspend fun connected(vararg devices: Device) =
        eventually("sessions between ${devices.map { it.name }}") {
            devices.all { device ->
                @Suppress("UNCHECKED_CAST")
                val peers = device.service.status()["peers"] as List<Map<String, Any?>>
                peers.count { it["state"] == "connected" } >= devices.size - 1
            }
        }

    @Test fun loginLogoutAndRestartPropagateBetweenDevices() =
        runBlocking {
            val a = Device("alpha", uoa.account("alice"))
            val b = Device("beta", uoa.account("alice"))
            connected(a, b)

            // Log in to a site on A: a persistent and a session cookie reach B.
            a.cookies.put(".example.com", "sid", "login-1")
            a.cookies.put("example.com", "csrf", "token-1", expires = null)
            a.changed()
            eventually("login reaches B") { b.cookies.value(".example.com", "sid") == "login-1" && b.cookies.value("example.com", "csrf") == "token-1" }

            // A change on B travels back to A.
            b.cookies.put(".example.com", "sid", "login-2")
            b.changed()
            eventually("change reaches A") { a.cookies.value(".example.com", "sid") == "login-2" }

            // Restart B: it loses its session cookie, warms up and gets it back from A
            // without telling A it was deleted.
            b.restart()
            assertNull(b.cookies.value("example.com", "csrf"))
            eventually("session cookie restored on B") { b.cookies.value("example.com", "csrf") == "token-1" }
            assertEquals("token-1", a.cookies.value("example.com", "csrf"))
            eventually("B warm-up ends") {
                @Suppress("UNCHECKED_CAST")
                (b.service.status()["store"] as Map<String, Any?>)["warming"] == false
            }

            // Log out of the site on A: both cookies disappear on B.
            a.cookies.remove(".example.com", "sid")
            a.cookies.remove("example.com", "csrf")
            a.changed()
            eventually("logout reaches B") { b.cookies.value(".example.com", "sid") == null && b.cookies.value("example.com", "csrf") == null }
            assertTrue(uoa.calls.get() >= 4)
        }

    @Test fun anotherAccountNeverReceivesCookies() =
        runBlocking {
            val a = Device("alpha", uoa.account("alice"))
            val honest = Device("bob", uoa.account("bob"))
            // An impostor advertising alice's hint but holding bob's UOA session.
            val impostor = Device("impostor", uoa.account("alice", ticketSubject = "bob"))
            a.cookies.put(".bank.test", "session", "alice-secret")
            a.changed()
            impostor.cookies.put(".bank.test", "planted", "bob-cookie")
            impostor.changed()

            // Whichever side initiates, one of them fails the UOA proof and no session carries data.
            eventually("impostor refused") {
                listOf(a, impostor).any { device ->
                    @Suppress("UNCHECKED_CAST")
                    val peers = device.service.status()["peers"] as List<Map<String, Any?>>
                    peers.any { it["lastError"] == "AUTH_FAILED" }
                }
            }
            delay(1_000)
            assertNull(impostor.cookies.value(".bank.test", "session"))
            assertNull(a.cookies.value(".bank.test", "planted"))
            assertNull(honest.cookies.value(".bank.test", "session"))
            @Suppress("UNCHECKED_CAST")
            val bobPeers = honest.service.status()["peers"] as List<Map<String, Any?>>
            assertTrue("bob ignores alice's hint", bobPeers.isEmpty())
        }

    @Test fun signOutStopsSyncAndSignInUnderAnotherSubjectKeepsCookiesLocal() =
        runBlocking {
            val a = Device("alpha", uoa.account("alice"))
            val b = Device("beta", uoa.account("alice"))
            connected(a, b)
            a.cookies.put(".mail.test", "sid", "alice")
            a.changed()
            eventually("cookie reaches B") { b.cookies.value(".mail.test", "sid") == "alice" }

            b.account.signOut()
            eventually("B stopped") { b.service.status()["listening"] == false }
            a.cookies.put(".mail.test", "sid", "alice-2")
            a.changed()
            delay(1_000)
            assertEquals("alice", b.cookies.value(".mail.test", "sid"))

            // B signs in as bob: alice's cookies already in B's store stay local.
            b.account.signIn("bob")
            val c = Device("gamma", uoa.account("bob"))
            connected(b, c)
            delay(1_000)
            assertNull(c.cookies.value(".mail.test", "sid"))
            c.cookies.put(".bob.test", "sid", "bob")
            c.changed()
            eventually("bob's cookie reaches B") { b.cookies.value(".bob.test", "sid") == "bob" }
            assertNull(a.cookies.value(".bob.test", "sid"))
        }
}
