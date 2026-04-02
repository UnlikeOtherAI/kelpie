package com.mollotov.browser.network

import android.webkit.WebView
import com.mollotov.browser.handlers.HandlerContext

typealias RouteHandler = suspend (body: Map<String, Any?>) -> Map<String, Any?>

class Router {
    private val routes = mutableMapOf<String, RouteHandler>()
    var webView: WebView? = null
    var handlerContext: HandlerContext? = null

    fun register(method: String, handler: RouteHandler) {
        routes[method] = handler
    }

    suspend fun handle(method: String, body: Map<String, Any?>): Pair<Int, Map<String, Any?>> {
        val handler = routes[method]
            ?: return 404 to mapOf(
                "success" to false,
                "error" to mapOf("code" to "NOT_FOUND", "message" to "Unknown method: $method"),
            )
        val result = handler(body)
        val success = result["success"] as? Boolean ?: false
        val status = if (success) 200 else if (result.containsKey("error")) 400 else 200

        val message = body["message"] as? String
        if (message != null) {
            handlerContext?.showToast(message)
        }

        return status to result
    }

    fun registerStubs() {
        val methods = listOf(
            "navigate", "back", "forward", "reload", "get-current-url",
            "screenshot", "get-dom", "query-selector", "query-selector-all",
            "get-element-text", "get-attributes", "click", "tap", "fill",
            "type", "select-option", "check", "uncheck", "scroll", "scroll2",
            "scroll-to-top", "scroll-to-bottom", "get-viewport", "get-device-info",
            "get-viewport-presets", "get-capabilities", "wait-for-element", "wait-for-navigation",
            "find-element", "find-button", "find-link", "find-input",
            "ai-status", "ai-load", "ai-unload", "ai-infer", "ai-record",
            "evaluate", "get-console-messages", "get-js-errors",
            "get-network-log", "get-resource-timeline", "clear-console",
            "get-accessibility-tree", "screenshot-annotated", "click-annotation",
            "fill-annotation", "get-visible-elements", "get-page-text",
            "get-form-state", "get-dialog", "handle-dialog",
            "set-dialog-auto-handler", "get-tabs", "new-tab", "switch-tab",
            "close-tab", "get-iframes", "switch-to-iframe", "switch-to-main",
            "get-iframe-context", "get-cookies", "set-cookie", "delete-cookies",
            "get-storage", "set-storage", "clear-storage", "watch-mutations",
            "get-mutations", "stop-watching", "query-shadow-dom",
            "get-shadow-roots", "get-clipboard", "set-clipboard",
            "set-geolocation", "clear-geolocation", "set-request-interception",
            "get-intercepted-requests", "clear-request-interception",
            "show-keyboard", "hide-keyboard", "get-keyboard-state",
            "resize-viewport", "reset-viewport", "set-viewport-preset", "is-element-obscured",
        )
        for (method in methods) {
            if (!routes.containsKey(method)) {
                register(method) {
                    mapOf(
                        "success" to false,
                        "error" to mapOf("code" to "NOT_IMPLEMENTED", "message" to "$method not yet implemented"),
                    )
                }
            }
        }
    }
}

fun errorResponse(code: String, message: String): Map<String, Any?> =
    mapOf("success" to false, "error" to mapOf("code" to code, "message" to message))

fun successResponse(data: Map<String, Any?> = emptyMap()): Map<String, Any?> =
    mutableMapOf<String, Any?>("success" to true).apply { putAll(data) }
