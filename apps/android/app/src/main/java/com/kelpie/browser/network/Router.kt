package com.kelpie.browser.network

import android.webkit.WebView
import com.kelpie.browser.handlers.HandlerContext

typealias RouteHandler = suspend (body: Map<String, Any?>) -> Map<String, Any?>

class Router {
    private val routes = mutableMapOf<String, RouteHandler>()
    var webView: WebView? = null
    var handlerContext: HandlerContext? = null
    var scriptPlaybackState: com.kelpie.browser.handlers.ScriptPlaybackState? = null

    /** Snapshot of currently-registered method names. */
    val registeredMethods: Set<String>
        get() = routes.keys.toSet()

    fun register(
        method: String,
        handler: RouteHandler,
    ) {
        routes[method] = handler
    }

    fun registerIfAbsent(
        method: String,
        handler: RouteHandler,
    ) {
        if (routes.containsKey(method)) {
            return
        }
        routes[method] = handler
    }

    suspend fun handle(
        method: String,
        body: Map<String, Any?>,
        bypassRecordingGate: Boolean = false,
    ): Pair<Int, Map<String, Any?>> {
        val handler =
            routes[method]
                ?: return 404 to
                    mapOf(
                        "success" to false,
                        "error" to mapOf("code" to "NOT_FOUND", "message" to "Unknown method: $method"),
                    )
        if (!bypassRecordingGate) {
            val gateError = scriptPlaybackState?.recordingError(method)
            if (gateError != null) {
                return 409 to gateError
            }
        }
        val result = handler(body)
        val success = result["success"] as? Boolean ?: false
        val errorCode = (result["error"] as? Map<*, *>)?.get("code") as? String
        val status =
            if (success) {
                200
            } else if (errorCode == "SCRIPT_PARTIAL_FAILURE" || errorCode == "SCRIPT_ABORTED" || result["aborted"] == true) {
                200
            } else if (result.containsKey("error")) {
                statusForErrorCode(errorCode)
            } else {
                200
            }

        val message = body["message"] as? String
        if (message != null) {
            handlerContext?.showToast(message)
        }

        return status to result
    }

    fun registerFallbacks() {
        for (method in AndroidUnsupportedMethods.all) {
            registerIfAbsent(method) {
                mapOf(
                    "success" to false,
                    "error" to
                        mapOf(
                            "code" to "PLATFORM_NOT_SUPPORTED",
                            "message" to "$method is not supported on Android",
                        ),
                )
            }
        }
    }
}

/**
 * Methods the Android app explicitly advertises as unsupported. This is the
 * single source of truth — DeviceHandler reads it for `get-capabilities`, and
 * the Router uses it to register fallback handlers for any method that no real
 * handler claims.
 */
object AndroidUnsupportedMethods {
    val all: Set<String> =
        setOf(
            "debug-screens",
            "set-debug-overlay",
            "get-debug-overlay",
            "set-geolocation",
            "clear-geolocation",
            "set-request-interception",
            "get-intercepted-requests",
            "clear-request-interception",
            "set-fullscreen",
            "get-fullscreen",
            "set-renderer",
            "get-renderer",
        )
}

fun errorResponse(
    code: String,
    message: String,
    diagnostics: Map<String, Any?>? = null,
): Map<String, Any?> {
    val error = mutableMapOf<String, Any?>("code" to code, "message" to message)
    if (diagnostics != null && diagnostics.isNotEmpty()) {
        error["diagnostics"] = diagnostics
    }
    return mapOf("success" to false, "error" to error)
}

fun successResponse(data: Map<String, Any?> = emptyMap()): Map<String, Any?> = mutableMapOf<String, Any?>("success" to true).apply { putAll(data) }

private fun statusForErrorCode(code: String?): Int =
    when (code) {
        "ELEMENT_NOT_FOUND",
        "WATCH_NOT_FOUND",
        -> 404
        "TIMEOUT" -> 408
        "NAVIGATION_ERROR" -> 502
        "PLATFORM_NOT_SUPPORTED" -> 501
        "IFRAME_ACCESS_DENIED",
        "PERMISSION_REQUIRED",
        "SHADOW_ROOT_CLOSED",
        -> 403
        "RECORDING_IN_PROGRESS" -> 409
        "WEBVIEW_ERROR" -> 500
        else -> 400
    }
