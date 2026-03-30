package com.mollotov.browser.handlers

import com.mollotov.browser.network.Router
import com.mollotov.browser.network.errorResponse
import com.mollotov.browser.network.successResponse
import kotlinx.coroutines.delay

class EvaluateHandler(private val ctx: HandlerContext) {
    fun register(router: Router) {
        router.register("evaluate") { evaluate(it) }
        router.register("wait-for-element") { waitForElement(it) }
        router.register("wait-for-navigation") { waitForNavigation(it) }
    }

    private suspend fun evaluate(body: Map<String, Any?>): Map<String, Any?> {
        val expression = body["expression"] as? String ?: return errorResponse("MISSING_PARAM", "expression is required")
        return try {
            val raw = ctx.evaluateJS(expression)
            successResponse(mapOf("result" to raw))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun waitForElement(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val timeout = (body["timeout"] as? Int) ?: 5000
        val state = body["state"] as? String ?: "visible"
        val safe = selector.replace("'", "\\'")
        val start = System.currentTimeMillis()

        while (System.currentTimeMillis() - start < timeout) {
            val js = "(function(){var el=document.querySelector('$safe');if(!el)return null;var r=el.getBoundingClientRect();return{tag:el.tagName.toLowerCase(),classes:Array.from(el.classList),visible:r.width>0&&r.height>0};})()"
            try {
                val result = ctx.evaluateJSReturningJSON(js)
                if (result.isNotEmpty()) {
                    val visible = result["visible"] as? Boolean ?: false
                    val matches = state == "attached" || (state == "visible" && visible) || (state == "hidden" && !visible)
                    if (matches) {
                        return successResponse(mapOf(
                            "element" to result,
                            "waitTime" to (System.currentTimeMillis() - start),
                        ))
                    }
                }
            } catch (_: Exception) {}
            delay(100)
        }
        return errorResponse("TIMEOUT", "Element did not reach state '$state' within ${timeout}ms")
    }

    private suspend fun waitForNavigation(body: Map<String, Any?>): Map<String, Any?> {
        val timeout = (body["timeout"] as? Int) ?: 10000
        val start = System.currentTimeMillis()

        while (System.currentTimeMillis() - start < timeout) {
            val result = ctx.evaluateJSReturningJSON("({readyState: document.readyState, url: location.href, title: document.title})")
            if (result["readyState"] == "complete") {
                return successResponse(mapOf(
                    "url" to (result["url"] ?: ""),
                    "title" to (result["title"] ?: ""),
                    "loadTime" to (System.currentTimeMillis() - start),
                ))
            }
            delay(100)
        }
        return errorResponse("TIMEOUT", "Navigation did not complete within ${timeout}ms")
    }
}
