package com.kelpie.browser.browser

import android.content.ContextWrapper
import android.content.SharedPreferences
import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.kelpie.browser.handlers.CookieHandlers
import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.handlers.MobileTabHandler
import com.kelpie.browser.network.BrowserGatewayBinding
import com.kelpie.browser.network.Router
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
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

/** Real WebViews and the production TabStore/cookie handler, without touching existing app sessions. */
@RunWith(AndroidJUnit4::class)
class SessionStorageTest {
    @Test
    fun legacyRequestsCreateAndInspectPartitionedWebViewsFromServerThreads() =
        runBlocking {
            val app = InstrumentationRegistry.getInstrumentation().targetContext
            val id = "dispatch-${UUID.randomUUID()}"
            val context =
                object : ContextWrapper(app) {
                    override fun getSharedPreferences(
                        name: String,
                        mode: Int,
                    ): SharedPreferences = app.getSharedPreferences("$id-$name", mode)
                }
            val handler = HandlerContext()
            val router = Router()
            val tabs =
                withContext(Dispatchers.Main) {
                    assumeTrue(PartitionRegistry.supported())
                    HistoryStore.init(context)
                    TabStore(context, handler, BrowserState()).also {
                        handler.tabStore = it
                        handler.webView = it.activeTab?.webView
                        MobileTabHandler(handler).register(router)
                        val cookies = CookieHandlers(handler)
                        router.register("get-cookies") { params -> cookies.getCookies(params) }
                        BrowserGatewayBinding(router, handler).register()
                    }
                }
            try {
                withContext(Dispatchers.Default) {
                    val created = router.handle("new-tab", mapOf("url" to "about:blank", "partition" to id))
                    assertEquals(200, created.first)
                    assertEquals(id, (created.second["tab"] as Map<*, *>)["partition"])
                    withContext(Dispatchers.Main) {
                        // Keep the visible binding stale, like the interval before
                        // Compose attaches a new tab. Dispatch must use TabStore.
                        val manager = PartitionRegistry.cookies(requireNotNull(tabs.activeTab).webView)
                        manager.setCookie("https://fixture.invalid", "dispatch_identity=isolated; Path=/; HttpOnly")
                        manager.flush()
                    }
                    val inspected = router.handle("get-cookies", mapOf("url" to "https://fixture.invalid"))
                    assertEquals(200, inspected.first)
                    assertEquals(true, inspected.second["success"])
                    assertTrue(inspected.second["cookies"].toString().contains("dispatch_identity"))
                }
            } finally {
                withContext(Dispatchers.Main) {
                    PartitionRegistry.delete(id, tabs)
                    tabs.destroyAllTabs()
                    SessionStore.clear(context)
                }
            }
        }

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
                    // Production initializes history in MainActivity before creating tabs.
                    HistoryStore.init(context)
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
                        first.webView.script("localStorage.setItem('$cookieName', 'shared')")
                        isolated.webView.script("localStorage.setItem('$cookieName', 'isolated')")
                        assertEquals("\"shared\"", second.webView.script("localStorage.getItem('$cookieName')"))
                        assertEquals("\"isolated\"", sibling.webView.script("localStorage.getItem('$cookieName')"))
                        assertEquals("null", other.webView.script("localStorage.getItem('$cookieName')"))
                        assertEquals("false", first.webView.script("document.cookie.includes('$cookieName')"))
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
                        tabs.tabs.value
                            .firstOrNull { it.partition == null }
                            ?.webView
                            ?.script("localStorage.removeItem('$cookieName')")
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

    private suspend fun WebView.script(expression: String): String =
        withTimeout(10_000) {
            suspendCoroutine { continuation -> evaluateJavascript(expression) { continuation.resume(it) } }
        }
}
