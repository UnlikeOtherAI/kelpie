package com.kelpie.browser.handlers

import android.os.Handler
import android.os.Looper
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import kotlinx.coroutines.delay

private val mainHandler = Handler(Looper.getMainLooper())

class NavigationHandler(private val ctx: HandlerContext) {
    fun register(router: Router) {
        router.register("navigate") { navigate(it) }
        router.register("back") { back() }
        router.register("forward") { forward() }
        router.register("reload") { reload() }
        router.register("get-current-url") { getCurrentUrl() }
        router.register("set-home") { setHome(it) }
        router.register("get-home") { getHome() }
    }

    private suspend fun navigate(body: Map<String, Any?>): Map<String, Any?> {
        val url = body["url"] as? String ?: return errorResponse("MISSING_PARAM", "url is required")
        val wv = ctx.webView ?: return errorResponse("NO_WEBVIEW", "No WebView")
        mainHandler.post { wv.loadUrl(url) }
        // Wait for page to start loading then finish
        delay(100)
        val timeout = (body["timeout"] as? Int) ?: 10000
        val start = System.currentTimeMillis()
        while (System.currentTimeMillis() - start < timeout) {
            val result = ctx.evaluateJSReturningJSON("({url: location.href, title: document.title, readyState: document.readyState})")
            if (result["readyState"] == "complete") {
                return successResponse(mapOf(
                    "url" to (result["url"] ?: url),
                    "title" to (result["title"] ?: ""),
                    "loadTime" to (System.currentTimeMillis() - start),
                ))
            }
            delay(100)
        }
        return successResponse(mapOf("url" to url, "title" to "", "loadTime" to timeout))
    }

    private suspend fun back(): Map<String, Any?> {
        val wv = ctx.webView ?: return errorResponse("NO_WEBVIEW", "No WebView")
        mainHandler.post { wv.goBack() }
        delay(200)
        val result = ctx.evaluateJSReturningJSON("({url: location.href, title: document.title})")
        return successResponse(result)
    }

    private suspend fun forward(): Map<String, Any?> {
        val wv = ctx.webView ?: return errorResponse("NO_WEBVIEW", "No WebView")
        mainHandler.post { wv.goForward() }
        delay(200)
        val result = ctx.evaluateJSReturningJSON("({url: location.href, title: document.title})")
        return successResponse(result)
    }

    private suspend fun reload(): Map<String, Any?> {
        val wv = ctx.webView ?: return errorResponse("NO_WEBVIEW", "No WebView")
        mainHandler.post { wv.reload() }
        delay(200)
        return successResponse(mapOf("url" to (wv.url ?: ""), "title" to (wv.title ?: "")))
    }

    private suspend fun getCurrentUrl(): Map<String, Any?> {
        val result = ctx.evaluateJSReturningJSON("({url: location.href, title: document.title})")
        return successResponse(result)
    }

    private fun setHome(body: Map<String, Any?>): Map<String, Any?> {
        val url = body["url"] as? String
        if (url.isNullOrEmpty()) return errorResponse("MISSING_PARAM", "url is required")
        com.kelpie.browser.browser.HomeStore.setUrl(url)
        return successResponse(mapOf("url" to url))
    }

    private fun getHome(): Map<String, Any?> {
        return successResponse(mapOf("url" to com.kelpie.browser.browser.HomeStore.url))
    }
}
