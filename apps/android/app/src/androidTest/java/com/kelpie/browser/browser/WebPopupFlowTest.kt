package com.kelpie.browser.browser

import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import com.kelpie.browser.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class WebPopupFlowTest {
    @get:Rule
    val ui = createAndroidComposeRule<MainActivity>()

    @Test
    fun popupKeepsOpenerAndClosesAfterPostingResult() {
        if (ui.onAllNodesWithText("Get Started").fetchSemanticsNodes().isNotEmpty()) {
            ui.onNodeWithText("Get Started").performClick()
        }
        val webView =
            ui.runOnIdle {
                val decor = ui.activity.window.decorView
                requireNotNull(decor.browserView())
            }
        ui.runOnIdle {
            webView.loadDataWithBaseURL(
                "https://popup.test/",
                """
                <title>Original page</title>
                <button onclick="window.postMessage('open', '*')">Sign in</button>
                <script>
                window.addEventListener('message', event => {
                    if (event.data === 'open') window.child = window.open('about:blank', 'sign-in', 'width=480,height=640');
                    else document.title = event.data;
                });
                </script>
                """.trimIndent(),
                "text/html",
                "utf-8",
                null,
            )
        }
        ui.waitUntil(5000) { evaluate(webView, "document.title") == "\"Original page\"" }
        ui.waitUntil(5000) { ui.runOnIdle { webView.hasWindowFocus() } }
        evaluate(webView, "document.querySelector('button').click()")
        ui.waitUntil(5000) { ui.runOnIdle { !webView.hasWindowFocus() } }
        assertEquals("true", evaluate(webView, "!!window.child && !window.child.closed"))
        assertEquals("\"Original page\"", evaluate(webView, "document.title"))
        evaluate(webView, "window.child.eval(\"setTimeout(() => { opener.postMessage('Signed in', '*'); close(); }, 0)\")")
        ui.waitUntil(5000) { evaluate(webView, "document.title") == "\"Signed in\"" }
        ui.waitUntil(5000) { evaluate(webView, "window.child.closed") == "true" }
        ui.waitUntil(5000) { ui.runOnIdle { webView.hasWindowFocus() } }
    }

    @Test
    fun newWindowLinkOpensSelectedTabAndKeepsOpenerPage() {
        if (ui.onAllNodesWithText("Get Started").fetchSemanticsNodes().isNotEmpty()) {
            ui.onNodeWithText("Get Started").performClick()
        }
        val webView = shownBrowserView()
        ui.runOnIdle {
            webView.loadDataWithBaseURL(
                "https://popup.test/",
                """
                <title>Workspaces</title>
                <button onclick="window.child = window.open('about:blank')">Open</button>
                """.trimIndent(),
                "text/html",
                "utf-8",
                null,
            )
        }
        ui.waitUntil(5000) { evaluate(webView, "document.title") == "\"Workspaces\"" }
        evaluate(webView, "document.querySelector('button').click()")
        ui.waitUntil(5000) { shownBrowserView() !== webView }
        val tab = shownBrowserView()
        assertEquals("true", evaluate(webView, "!!window.child && !window.child.closed"))
        assertEquals("true", evaluate(tab, "window.opener !== null"))
        assertEquals("\"Workspaces\"", evaluate(webView, "document.title"))
        evaluate(webView, "window.child.close()")
        ui.waitUntil(5000) { shownBrowserView() === webView }
    }

    private fun shownBrowserView(): WebView {
        val decor = ui.runOnIdle { ui.activity.window.decorView }
        return ui.runOnIdle { requireNotNull(decor.browserView()) }
    }

    private fun evaluate(
        webView: WebView,
        script: String,
    ): String? {
        val complete = CountDownLatch(1)
        var result: String? = null
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            webView.evaluateJavascript(script) {
                result = it
                complete.countDown()
            }
        }
        check(complete.await(5, TimeUnit.SECONDS)) { "WebView evaluation timed out" }
        return result
    }

    private fun View.browserView(): WebView? {
        if (this is WebView) return this
        if (this is ViewGroup) {
            for (index in 0 until childCount) getChildAt(index).browserView()?.let { return it }
        }
        return null
    }
}
