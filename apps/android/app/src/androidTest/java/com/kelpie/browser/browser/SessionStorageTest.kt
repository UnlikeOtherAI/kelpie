package com.kelpie.browser.browser

import android.content.ContextWrapper
import android.content.SharedPreferences
import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.kelpie.browser.handlers.CookieHandlers
import com.kelpie.browser.handlers.HandlerContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

/** Real WebViews and the production TabStore/cookie handler, without touching existing app sessions. */
@RunWith(AndroidJUnit4::class)
class SessionStorageTest {
    @Test
    fun ordinaryTabsShareHttpOnlySessionsWhileNamedStoresStaySeparate() =
        runBlocking {
            val server = MockWebServer()
            server.dispatcher =
                object : Dispatcher() {
                    override fun dispatch(request: RecordedRequest): MockResponse =
                        MockResponse()
                            .setHeader("Content-Type", "text/html")
                            .setBody("<title>Session fixture</title><p>Ready</p>")
                }
            server.start()
            val url = server.url("/").toString()
            try {
                withContext(Dispatchers.Main) {
                    assumeTrue(PartitionRegistry.supported())
                    val id = "session-${UUID.randomUUID()}"
                    val app = InstrumentationRegistry.getInstrumentation().targetContext
                    val context =
                        object : ContextWrapper(app) {
                            override fun getSharedPreferences(
                                name: String,
                                mode: Int,
                            ): SharedPreferences = app.getSharedPreferences("$id-$name", mode)
                        }
                    val handler = HandlerContext()
                    var tabs = TabStore(context, handler, BrowserState())
                    handler.tabStore = tabs
                    val cookieName = "session_${UUID.randomUUID().toString().replace("-", "")}"
                    try {
                        val first = tabs.addTab(url)
                        val second = tabs.addTab(url)
                        val isolated = tabs.addTab(url, partition = id)
                        val sibling = tabs.addTab(url, partition = id)
                        val other = tabs.addTab(url, partition = "$id-other")
                        withTimeout(10_000) {
                            while (listOf(first, second, isolated, sibling, other).any { it.isLoading || it.pageTitle != "Session fixture" }) delay(20)
                        }
                        handler.webView = first.webView
                        val cookies = CookieHandlers(handler)
                        cookies.setCookie(mapOf("url" to url, "name" to cookieName, "value" to "shared", "httpOnly" to true))
                        handler.webView = second.webView
                        assertTrue(cookies.getCookies(mapOf("url" to url)).toString().contains("shared"))
                        handler.webView = isolated.webView
                        assertFalse(cookies.getCookies(mapOf("url" to url)).toString().contains(cookieName))
                        cookies.setCookie(mapOf("url" to url, "name" to cookieName, "value" to "isolated", "httpOnly" to true))
                        handler.webView = sibling.webView
                        assertTrue(cookies.getCookies(mapOf("url" to url)).toString().contains("isolated"))
                        handler.webView = other.webView
                        assertFalse(cookies.getCookies(mapOf("url" to url)).toString().contains(cookieName))
                        // The native login's default-profile WebView sees the ordinary session.
                        val login = WebView(context)
                        assertTrue(
                            PartitionRegistry
                                .cookies(login)
                                .getCookie(url)
                                .orEmpty()
                                .contains("$cookieName=shared"),
                        )
                        login.destroy()
                        tabs.persistSession()
                        val profile = PartitionRegistry.resolve(id)
                        tabs.destroyAllTabs()
                        tabs = TabStore(context, handler, BrowserState())
                        handler.tabStore = tabs
                        assertEquals(2, tabs.tabs.value.count { it.partition == id })
                        assertEquals(profile, PartitionRegistry.resolve(id, restoring = true))
                        handler.webView =
                            tabs.tabs.value
                                .first { it.partition == id }
                                .webView
                        assertTrue(cookies.getCookies(mapOf("url" to url)).toString().contains("isolated"))
                        val deleted = PartitionRegistry.delete(id, tabs)
                        assertEquals("PARTITION_IN_USE", (deleted["error"] as Map<*, *>)["code"])
                        assertTrue(PartitionRegistry.listing(tabs.tabs.value).any { it["id"] == "orphan:$profile" })
                        assertNotEquals(profile, PartitionRegistry.resolve(id))
                        val fresh = tabs.addTab(url, partition = id)
                        assertNull(PartitionRegistry.cookies(fresh.webView).getCookie(url))
                    } finally {
                        // Expire just this test cookie; never clear the person's cookie jar.
                        android.webkit.CookieManager
                            .getInstance()
                            .setCookie(url, "$cookieName=; Max-Age=0; Path=/")
                        PartitionRegistry.delete(id, tabs)
                        PartitionRegistry.delete("$id-other", tabs)
                        tabs.destroyAllTabs()
                        SessionStore.clear(context)
                    }
                }
            } finally {
                server.shutdown()
            }
        }
}
