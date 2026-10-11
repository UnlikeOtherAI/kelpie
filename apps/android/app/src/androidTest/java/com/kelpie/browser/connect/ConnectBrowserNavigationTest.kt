package com.kelpie.browser.connect

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.kelpie.browser.browser.BrowserState
import com.kelpie.browser.browser.TabStore
import com.kelpie.browser.handlers.HandlerContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Local emulator regression: uses the production TabStore, WebViewClient, router and handlers. */
@RunWith(AndroidJUnit4::class)
class ConnectBrowserNavigationTest {
    @Test
    fun snapshotSelectorsIdentifyDuplicateButtonsAndEmptyInputs() = runBlocking {
        fixture { browser, context, server, _ ->
            val tab = context.tabStore!!.activeTab!!
            tab.webView.layout(0, 0, 800, 600)
            tab.webView.loadDataWithBaseURL(url(server, "/controls"), "<title>Controls</title><button class='same'>Go</button><button class='same'>Go</button><input>", "text/html", "utf-8", null)
            withTimeout(5000) { do { delay(30) } while (tab.isLoading || tab.pageTitle != "Controls") }
            val result = browser.execute(mapOf("operation" to "snapshot", "tabId" to tab.id, "tabVersion" to tab.documentVersion, "input" to emptyMap<String, Any>()))
            val page = result["page"] as Map<*, *>
            val elements = page["elements"] as List<*>
            val selectors = elements.map { (it as Map<*, *>)["selector"] as String }
            assertEquals(3, selectors.size)
            assertEquals(3, selectors.toSet().size)
            for (selector in selectors) {
                assertTrue(selector.length <= 2000)
                val found = context.evaluateJSReturningJSON("({count:document.querySelectorAll(${org.json.JSONObject.quote(selector)}).length})")
                assertEquals(1, (found["count"] as Number).toInt())
            }
        }
    }
    @Test
    fun extractionCancellationCannotCancelAnotherRequest() = runBlocking {
        val extraction = com.kelpie.browser.ai.InferenceRequest()
        val personChat = com.kelpie.browser.ai.InferenceRequest()
        try {
            extraction.cancel()
            val stopped = com.kelpie.browser.ai.LocalInference.execute("infer", mapOf("prompt" to "Hello"), extraction)
            assertEquals("INFERENCE_CANCELLED", (stopped["error"] as Map<*, *>)["code"])
            val status = com.kelpie.browser.ai.LocalInference.execute("status", request = personChat)
            assertEquals(true, status["success"])
        } finally {
            extraction.close()
            personChat.close()
        }
    }
    @Test
    fun navigationReturnsItsNewDocumentPin() =
        runBlocking {
            fixture { browser, context, server, _ ->
                server.enqueue(page("Owned destination"))
                val tab = context.tabStore!!.activeTab!!
                val previous = tab.documentVersion
                val result = browser.execute(command(context, url(server, "/destination")))
                assertEquals(tab.id, result["tabId"])
                assertEquals(tab.documentVersion, result["tabVersion"])
                assertNotEquals(previous, result["tabVersion"])
                assertEquals("Owned destination", (result["result"] as Map<*, *>)["title"])
            }
        }

    @Test
    fun cancellationAndUserTabChangeRefuseCompletion() =
        runBlocking {
            for (switchTab in listOf(false, true)) {
                fixture { browser, context, server, authority ->
                    val permit = CountDownLatch(1)
                    server.dispatcher =
                        object : Dispatcher() {
                            override fun dispatch(request: RecordedRequest): MockResponse {
                                check(permit.await(5, TimeUnit.SECONDS))
                                return page("Delayed")
                            }
                        }
                    val execution =
                        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.currentCoroutineContext()).async {
                            runCatching { browser.execute(command(context, url(server, "/delayed"))) }
                        }
                    withContext(Dispatchers.IO) { check(server.takeRequest(5, TimeUnit.SECONDS) != null) }
                    if (switchTab) context.tabStore!!.addTab() else authority.allowed = false
                    permit.countDown()
                    assertTrue("Must refuse completion after user tab change=$switchTab", execution.await().isFailure)
                }
            }
        }

    @Test
    fun unrelatedRedirectCannotBorrowCompletionPin() =
        runBlocking {
            fixture { browser, context, server, _ ->
                server.enqueue(MockResponse().setResponseCode(302).addHeader("Location", url(server, "/other")))
                server.enqueue(page("Redirected"))
                assertTrue(runCatching { browser.execute(command(context, url(server, "/requested"))) }.isFailure)
            }
        }

    private class Authority {
        var allowed = true
    }

    @Test
    fun pageContextReadsKeepTheBeforeAndAfterJobFence() =
        runBlocking {
            fixture { _, context, _, _ ->
                context.remoteDocumentGuard = { false }
                assertTrue(
                    runCatching {
                        com.kelpie.browser.llm.PageTextSnapshot
                            .read(context, emptyMap())
                    }.isFailure,
                )
                var checks = 0
                context.remoteDocumentGuard = { ++checks == 1 }
                assertTrue(
                    runCatching {
                        com.kelpie.browser.llm.PageTextSnapshot
                            .read(context, emptyMap())
                    }.isFailure,
                )
                assertEquals(2, checks)
            }
        }

    private suspend fun fixture(block: suspend (ConnectBrowser, HandlerContext, MockWebServer, Authority) -> Unit) {
        val server = MockWebServer()
        server.start()
        try {
            withContext(Dispatchers.Main) {
                val app = InstrumentationRegistry.getInstrumentation().targetContext
                check(app.packageName.endsWith(".nessieverify")) { "Requires the isolated verification profile" }
                com.kelpie.browser.browser.HistoryStore
                    .init(app)
                com.kelpie.browser.browser.HomeStore
                    .init(app)
                com.kelpie.browser.browser.SessionStore
                    .clear(app)
                val context = HandlerContext()
                val store = TabStore(app, context, BrowserState())
                context.tabStore = store
                // Own verification profile only; establish a settled initial document through its real clients.
                val tab = store.addTab()
                context.webView = tab.webView
                tab.webView.loadDataWithBaseURL(url(server, "/initial"), "<title>Initial</title>", "text/html", "utf-8", null)
                withTimeout(5000) {
                    do {
                        delay(50)
                    } while (tab.isLoading || tab.pageTitle != "Initial")
                }
                val authority = Authority()
                val expires = System.nanoTime() + TimeUnit.SECONDS.toNanos(8)
                val browser = ConnectBrowser(context, app.cacheDir) { authority.allowed && System.nanoTime() < expires }
                try {
                    withTimeout(10000) { block(browser, context, server, authority) }
                } finally {
                    store.destroyAllTabs()
                }
            }
        } finally {
            server.shutdown()
        }
    }

    private fun command(
        context: HandlerContext,
        url: String,
    ): Map<String, Any?> =
        mapOf(
            "operation" to "navigate",
            "tabId" to context.tabStore!!.activeTab!!.id,
            "tabVersion" to context.tabStore!!.activeTab!!.documentVersion,
            "input" to mapOf("url" to url),
        )

    private fun url(
        server: MockWebServer,
        path: String,
    ) = "http://127.0.0.1:${server.port}$path"

    private fun page(title: String) = MockResponse().setHeader("Content-Type", "text/html").setBody("<title>$title</title><p>Local fixture</p>")
}
