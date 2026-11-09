package com.kelpie.browser.sync

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** getCookieInfo lines as WebView 156 (Android 14) and WebView 124 (Android 15) returned them. */
class WebViewCookieSourceTests {
    private val hostOnly = "hostonly=1; domain=www.probe.kelpie-sync.test; path=/; expires=Tue, 14 Dec 2027 18:53:08 GMT; secure; httponly; samesite=strict"
    private val domain = "domaincookie=2; domain=.www.probe.kelpie-sync.test; path=/; expires=Tue, 14 Dec 2027 18:53:08 GMT; samesite=lax"
    private val session = "nosamesite=8; domain=www.probe.kelpie-sync.test; path=/"
    private val partitioned = "chips=7; domain=www.probe.kelpie-sync.test; path=/; secure; partitioned; samesite=none"

    @Test fun parsesHostOnlyAndDomainCookiesApart() {
        val host = SetCookieLine.parse(hostOnly)!!
        assertEquals("www.probe.kelpie-sync.test", host.domain)
        assertEquals("/", host.path)
        assertEquals(1828810388L, host.expires)
        assertTrue(host.secure)
        assertTrue(host.httpOnly)
        assertEquals("Strict", host.sameSite)
        val dom = SetCookieLine.parse(domain)!!
        assertEquals(".www.probe.kelpie-sync.test", dom.domain)
        assertEquals("www.probe.kelpie-sync.test", dom.host)
        assertFalse(dom.secure)
        assertFalse(dom.httpOnly)
        assertEquals("Lax", dom.sameSite)
    }

    @Test fun sessionCookiesHaveNoExpiryAndUnspecifiedSameSite() {
        val parsed = SetCookieLine.parse(session)!!
        assertNull(parsed.expires)
        assertEquals("Unspecified", parsed.sameSite)
        assertEquals("None", SetCookieLine.parse("n=5; domain=a.test; path=/; secure; samesite=none")!!.sameSite)
        assertEquals("/account", SetCookieLine.parse("p=4; domain=a.test; path=/account")!!.path)
    }

    @Test fun refusesWhatSyncCannotDescribe() {
        assertTrue(SetCookieLine.parse(partitioned)!!.partitioned)
        assertNull(SetCookieLine.parse("valueonly; domain=a.test; path=/"))
        assertNull(SetCookieLine.parse("a=1; path=/"))
        assertNull(SetCookieLine.parse("a=1; domain=a.test"))
        assertNull(SetCookieLine.parse("a=1; domain=a.test; path=/; samesite=bogus"))
        assertNull(SetCookieLine.parse("a=1; domain=a.test; path=/; expires=tomorrow"))
        assertEquals("v=x", SetCookieLine.parse("a=v=x; domain=a.test; path=/")!!.value)
    }

    @Test fun writesRoundTripThroughTheParser() {
        val wire = SetCookieLine.parse(hostOnly)!!.wire()
        assertEquals(
            "hostonly=1; Path=/; Expires=Tue, 14 Dec 2027 18:53:08 GMT; Secure; HttpOnly; SameSite=Strict",
            SetCookieLine.forWrite(wire),
        )
        assertEquals(
            "domaincookie=2; Domain=www.probe.kelpie-sync.test; Path=/; Expires=Tue, 14 Dec 2027 18:53:08 GMT; SameSite=Lax",
            SetCookieLine.forWrite(SetCookieLine.parse(domain)!!.wire()),
        )
        assertEquals("a=; Path=/x; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure", SetCookieLine.forDelete("a.test", "/x", "a"))
        assertEquals("a=; Domain=a.test; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure", SetCookieLine.forDelete(".a.test", "/", "a"))
        assertEquals("https://a.test/x", SetCookieLine.url(".a.test", "/x"))
        assertEquals("https://[2001:db8::1]/", SetCookieLine.url("2001:db8::1"))
    }

    @Test fun coverageCoversEntriesHistoryAndRecentPages() {
        val urls =
            CoverageUrls.build(
                entries = listOf(EntryLocation(".example.com", "/"), EntryLocation("www.example.com", "/account"), EntryLocation("localhost", "/")),
                hosts = null,
                historyHosts = listOf("news.test", "news.test", "127.0.0.1"),
                recentUrls = listOf("https://shop.test/cart?x=1", "about:blank"),
            )
        assertEquals(
            listOf("https://example.com/", "https://www.example.com/account", "https://news.test/", "https://shop.test/", "https://shop.test/cart"),
            urls,
        )
        val limited = CoverageUrls.build(listOf(EntryLocation(".example.com", "/a"), EntryLocation("other.test", "/")), setOf("example.com"), emptyList(), emptyList())
        assertEquals(listOf("https://example.com/a", "https://example.com/"), limited)
    }

    private class FakeEngine(
        val failing: Set<String> = emptySet(),
    ) : CookieInfoEngine {
        val cookies = mutableMapOf<String, MutableList<String>>() // url → lines
        val writes = mutableListOf<Pair<String, String>>()

        override fun info(url: String): List<String> {
            if (url in failing) error("query failed")
            return cookies[url].orEmpty()
        }

        override fun set(
            url: String,
            header: String,
        ) {
            writes.add(url to header)
        }

        override fun flush() = Unit
    }

    @Test fun snapshotReportsUrlCoverageAndSkipsPartitionedCookies() {
        val engine = FakeEngine()
        engine.cookies["https://www.probe.kelpie-sync.test/"] = mutableListOf(hostOnly, domain, partitioned)
        val source = WebViewCookieSource(engine, { emptyList() }, RecentLoads({ 0L }))
        val snapshot = source.snapshot(listOf(EntryLocation("www.probe.kelpie-sync.test", "/")))
        assertEquals(2, snapshot.cookies.size)
        assertEquals(listOf("https://www.probe.kelpie-sync.test/"), snapshot.coverage["urls"]!!.jsonArray.map { it.jsonPrimitive.content })
        val first = snapshot.cookies[0].jsonObject
        assertEquals(1828810388L, first["expires"]!!.jsonPrimitive.content.toLong())
    }

    @Test fun aFailedQueryAbortsTheScan() {
        val engine = FakeEngine(failing = setOf("https://b.test/"))
        val source = WebViewCookieSource(engine, { listOf("a.test", "b.test") }, RecentLoads({ 0L }))
        val failure = runCatching { source.snapshot(emptyList()) }.exceptionOrNull()
        assertEquals("SCAN_FAILED", (failure as SyncFailure).code)
    }

    private fun op(
        kind: String,
        cookie: JsonObject,
    ) = buildJsonObject {
        put("id", 0)
        put("op", kind)
        put("cookie", cookie)
    }

    @Test fun applyReadsBackEveryVariantOfTheNameForTheHost() {
        val engine = FakeEngine()
        val host = "https://www.probe.kelpie-sync.test/"
        engine.cookies[host] =
            mutableListOf(
                "dup=hostonly; domain=www.probe.kelpie-sync.test; path=/",
                "dup=domain; domain=.www.probe.kelpie-sync.test; path=/",
                "dup=parent; domain=.probe.kelpie-sync.test; path=/",
                "other=1; domain=www.probe.kelpie-sync.test; path=/",
            )
        val source = WebViewCookieSource(engine, { emptyList() }, RecentLoads({ 0L }))
        val cookie =
            buildJsonObject {
                put("domain", ".www.probe.kelpie-sync.test")
                put("path", "/")
                put("name", "dup")
                put("value", "domain")
                put("expires", JsonPrimitive(null as Long?))
                put("secure", false)
                put("httpOnly", false)
                put("sameSite", "Unspecified")
            }
        val result = source.apply(op("set", cookie), emptyList())
        assertEquals(true, result["ok"]!!.jsonPrimitive.content.toBoolean())
        val domains = result["readback"]!!.jsonArray.map { it.jsonObject["domain"]!!.jsonPrimitive.content }.toSet()
        assertEquals(setOf("www.probe.kelpie-sync.test", ".www.probe.kelpie-sync.test"), domains)
        assertEquals(host to "dup=domain; Domain=www.probe.kelpie-sync.test; Path=/", engine.writes.single())
    }

    @Test fun aFailedReadBackIsNotOk() {
        val engine = FakeEngine(failing = setOf("https://a.test/"))
        val source = WebViewCookieSource(engine, { emptyList() }, RecentLoads({ 0L }))
        val cookie =
            buildJsonObject {
                put("domain", "a.test")
                put("path", "/")
                put("name", "gone")
            }
        val result = source.apply(op("delete", cookie), emptyList())
        assertEquals("false", result["ok"]!!.jsonPrimitive.content)
        assertEquals(0, result["readback"]!!.jsonArray.size)
    }
}
