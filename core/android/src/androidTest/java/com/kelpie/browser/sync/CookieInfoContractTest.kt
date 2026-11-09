package com.kelpie.browser.sync

import android.util.Log
import android.webkit.CookieManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.webkit.WebViewFeature
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The cookie adapter against a real WebView default store: getCookieInfo keeps
 * host-only and domain cookies apart and carries every attribute; sync writes,
 * read-backs and deletes round-trip HttpOnly cookies. Logs the scan cost.
 */
@RunWith(AndroidJUnit4::class)
class CookieInfoContractTest {
    private val host = "www.probe.kelpie-sync.test"
    private lateinit var manager: CookieManager
    private lateinit var source: WebViewCookieSource

    @Before fun setUp() {
        assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO))
        main { manager = CookieManager.getInstance() }
        source = WebViewCookieSource(CookieSync.ManagerEngine(manager), { emptyList() }, RecentLoads(System::currentTimeMillis))
    }

    @After fun tearDown() =
        main {
            if (::manager.isInitialized) {
                manager.removeAllCookies(null)
                manager.flush()
            }
        }

    private fun main(block: () -> Unit) = InstrumentationRegistry.getInstrumentation().runOnMainSync(block)

    private fun set(vararg headers: String) {
        headers.forEach { manager.setCookie("https://$host/", it) }
        manager.flush()
    }

    private fun lines(url: String = "https://$host/"): List<SetCookieLine.Parsed> = CookieSync.ManagerEngine(manager).info(url).mapNotNull(SetCookieLine::parse)

    @Test fun hostOnlyAndDomainCookiesStayDistinctWithEveryAttribute() {
        set(
            "hostonly=1; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=3600",
            "domaincookie=2; Domain=$host; Path=/; SameSite=Lax",
            "none=3; Secure; SameSite=None; Path=/",
            "plain=4; Path=/",
            "chips=5; Secure; SameSite=None; Path=/; Partitioned",
        )
        val byName = lines().associateBy { it.name }
        val hostOnly = byName.getValue("hostonly")
        assertEquals(host, hostOnly.domain)
        assertTrue(hostOnly.secure && hostOnly.httpOnly)
        assertEquals("Strict", hostOnly.sameSite)
        assertNotNull(hostOnly.expires)
        assertEquals(".$host", byName.getValue("domaincookie").domain)
        assertEquals("Lax", byName.getValue("domaincookie").sameSite)
        assertEquals("None", byName.getValue("none").sameSite)
        assertEquals("Unspecified", byName.getValue("plain").sameSite)
        assertNull(byName.getValue("plain").expires)
        assertTrue(byName.getValue("chips").partitioned)
        val snapshot = source.snapshot(listOf(EntryLocation(host, "/")))
        assertEquals(setOf("hostonly", "domaincookie", "none", "plain"), snapshot.cookies.map { it.jsonObject.string("name") }.toSet())
    }

    @Test fun syncWritesReadBackAndDeleteHttpOnlyCookies() {
        val cookie =
            buildJsonObject {
                put("domain", ".$host")
                put("path", "/account")
                put("name", "sid")
                put("value", "synced")
                put("expires", System.currentTimeMillis() / 1000 + 86_400)
                put("secure", true)
                put("httpOnly", true)
                put("sameSite", "Lax")
            }
        set("sid=hostvariant; Path=/account")
        val written = source.apply(op("set", cookie), emptyList())
        assertEquals("true", written["ok"]!!.jsonPrimitive.content)
        val readback = written["readback"]!!.jsonArray.map { it.jsonObject }
        assertEquals(setOf(host, ".$host"), readback.map { it.string("domain") }.toSet())
        val stored = readback.single { it.string("domain") == ".$host" }
        assertEquals("synced", stored.string("value"))
        assertEquals("/account", stored.string("path"))
        assertEquals(true, stored.bool("httpOnly"))
        assertEquals(cookie.long("expires"), stored.long("expires"))

        val removed = source.apply(op("delete", cookie), emptyList())
        val left = removed["readback"]!!.jsonArray.map { it.jsonObject.string("domain") }
        assertEquals(listOf(host), left) // only the host-only variant remains
    }

    @Test fun measuresScanCost() {
        // Distinct registrable domains: Chromium caps cookies per eTLD+1 (180), not per host.
        val entries = (0 until 200).map { EntryLocation("www.kelpie-sync-$it.test", "/") }
        main { entries.forEach { manager.setCookie("https://${it.domain}/", "c=1; Path=/") } }
        manager.flush()
        source.snapshot(entries.take(10))
        val started = System.nanoTime()
        val snapshot = source.snapshot(entries)
        val millis = (System.nanoTime() - started) / 1_000_000.0
        Log.i("KelpieCookieSync", "scan cost: ${entries.size} urls, ${snapshot.cookies.size} cookies, $millis ms")
        assertEquals(200, snapshot.cookies.size)
    }

    private fun op(
        kind: String,
        cookie: JsonObject,
    ) = buildJsonObject {
        put("id", 0)
        put("op", kind)
        put("cookie", cookie)
    }
}
