package com.kelpie.browser.sync

import android.webkit.CookieManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.webkit.WebViewFeature
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Cookie sync on a real device: one service runs over this process's WebView
 * default store (the Android adapter), the other over an in-memory store. They
 * meet over real loopback HTTP with real crypto and core-sync; UOA is faked.
 * Also checks that NSD advertises and resolves `_kelpie-sync._tcp` with its TXT.
 */
@RunWith(AndroidJUnit4::class)
class CookieSyncDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val uoa = FakeUOA()
    private val network = LoopbackDiscovery.Network()
    private val services = mutableListOf<CookieSyncService>()
    private lateinit var manager: CookieManager
    private val host = "sync.kelpie-device.test"

    @Before fun setUp() {
        assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO))
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            manager = CookieManager.getInstance()
            manager.removeAllCookies(null)
            manager.flush()
        }
    }

    @After fun tearDown() =
        runBlocking {
            services.forEach { it.stop() }
            manager.removeAllCookies(null)
            manager.flush()
        }

    private fun service(
        name: String,
        cookies: CookieSource,
        recent: RecentLoads,
    ) = CookieSyncService(
        account = uoa.account("alice"),
        cookies = cookies,
        directory = File(context.cacheDir, "sync-test-$name-${System.nanoTime()}"),
        discovery = LoopbackDiscovery(network),
        subnets = AndroidSyncSubnets(context),
        transport = SyncHttpTransport(),
        deviceName = name,
        recent = recent,
        launches = SyncLaunches(),
        timings = SyncTimings(pageLoadQuietMs = 50, warmupPeerWindowMs = 1_000, warmupMaxMs = 4_000, fallbackInitiateMs = 2_000),
    ).also {
        services.add(it)
        it.start()
    }

    private suspend fun eventually(
        what: String,
        check: suspend () -> Boolean,
    ) {
        try {
            withTimeout(30_000) { while (!check()) delay(200) }
        } catch (error: kotlinx.coroutines.TimeoutCancellationException) {
            throw AssertionError("timed out waiting for: $what")
        }
    }

    private fun webCookie(name: String): SetCookieLine.Parsed? =
        CookieSync
            .ManagerEngine(manager)
            .info("https://$host/")
            .mapNotNull(SetCookieLine::parse)
            .firstOrNull { it.name == name }

    @Test fun webViewStoreSyncsBothWays() =
        runBlocking {
            val recent = RecentLoads(System::currentTimeMillis)
            val device = service("webview", WebViewCookieSource(CookieSync.ManagerEngine(manager), { emptyList() }, recent), recent)
            val memory = MemoryCookies()
            val peer = service("memory", memory, RecentLoads(System::currentTimeMillis))

            // A site sets an HttpOnly login cookie in the WebView; the page-load scan sends it.
            manager.setCookie("https://$host/", "sid=device-login; Domain=$host; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=86400")
            manager.flush()
            device.pageLoaded(host, "https://$host/")
            eventually("WebView login reaches the peer") { memory.value(".$host", "sid") == "device-login" }

            // The peer logs in again; the WebView store gets the new HttpOnly value.
            memory.put(".$host", "sid", "peer-login")
            peer.scan()
            eventually("peer change reaches the WebView") { webCookie("sid")?.value == "peer-login" }
            val synced = webCookie("sid")!!
            assertEquals(".$host", synced.domain)
            assertTrue(synced.httpOnly && synced.secure)
            assertEquals("Lax", synced.sameSite)

            // Logging out of the site in the WebView removes it on the peer.
            manager.setCookie("https://$host/", SetCookieLine.forDelete(".$host", "/", "sid"))
            manager.flush()
            device.pageLoaded(host, "https://$host/")
            eventually("WebView logout reaches the peer") { memory.value(".$host", "sid") == null }

            @Suppress("UNCHECKED_CAST")
            val peers = device.status()["peers"] as List<Map<String, Any?>>
            assertEquals("connected", peers.single()["state"])
        }

    @Test fun nsdAdvertisesAndResolvesTheSyncService() =
        runBlocking {
            val advertiser = NsdSyncDiscovery(context)
            val browser = NsdSyncDiscovery(context)
            val replica = SyncBase64.encode(ByteArray(16).also { java.security.SecureRandom().nextBytes(it) })
            val hint = SyncCore.hints("alice", System.currentTimeMillis()).first
            val found = kotlinx.coroutines.CompletableDeferred<SyncDiscovery.Found>()
            val quiet =
                object : SyncDiscovery.Listener {
                    override fun found(peer: SyncDiscovery.Found) = Unit

                    override fun lost(replica: String) = Unit
                }
            try {
                advertiser.start(SyncDiscovery.Advert(replica, hint, 45_678), quiet)
                browser.start(
                    SyncDiscovery.Advert(SyncBase64.encode(ByteArray(16)), hint, 45_679),
                    object : SyncDiscovery.Listener {
                        override fun found(peer: SyncDiscovery.Found) {
                            if (peer.replica == replica) found.complete(peer)
                        }

                        override fun lost(replica: String) = Unit
                    },
                )
                val peer = withTimeout(30_000) { found.await() }
                assertEquals(hint, peer.hint)
                assertEquals(45_678, peer.port)
                assertTrue(peer.addresses.isNotEmpty())
            } finally {
                advertiser.stop()
                browser.stop()
            }
        }
}
