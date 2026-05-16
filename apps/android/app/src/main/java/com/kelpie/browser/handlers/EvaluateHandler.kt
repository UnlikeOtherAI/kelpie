package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import kotlinx.coroutines.delay
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

private val evaluateJson =
    Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

class EvaluateHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("evaluate") { evaluate(it) }
        router.register("wait-for-element") { waitForElement(it) }
        router.register("wait-for-navigation") { waitForNavigation(it) }
    }

    private suspend fun evaluate(body: Map<String, Any?>): Map<String, Any?> {
        val expression = body["expression"] as? String ?: return errorResponse("MISSING_PARAM", "expression is required")
        return try {
            // WebView.evaluateJavascript always returns a JSON literal (or "null").
            // Parse it so the API matches the EvaluateResponse contract
            // (result: unknown) instead of always returning a raw string.
            val raw = ctx.evaluateJS(expression)
            val parsed = parseEvaluateResult(raw)
            successResponse(mapOf("result" to parsed))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private fun parseEvaluateResult(raw: String): Any? {
        if (raw.isBlank() || raw == "null") return null
        return try {
            jsonElementToAny(evaluateJson.parseToJsonElement(raw))
        } catch (_: Exception) {
            raw
        }
    }

    private fun jsonElementToAny(element: JsonElement): Any? =
        when (element) {
            is JsonNull -> null
            is JsonPrimitive -> {
                when {
                    element.isString -> element.content
                    element.content == "true" -> true
                    element.content == "false" -> false
                    element.content.contains('.') -> element.content.toDoubleOrNull() ?: element.content
                    else -> element.content.toIntOrNull() ?: element.content.toLongOrNull() ?: element.content
                }
            }
            is JsonObject -> element.entries.associate { (k, v) -> k to jsonElementToAny(v) }
            is JsonArray -> element.map { jsonElementToAny(it) }
        }

    private suspend fun waitForElement(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val timeout = (body["timeout"] as? Int) ?: 5000
        val state = body["state"] as? String ?: "visible"
        val safe = selector.replace("'", "\\'")
        val start = System.currentTimeMillis()

        while (System.currentTimeMillis() - start < timeout) {
            val js =
                "(function(){var el=document.querySelector('$safe');" +
                    "if(!el)return null;var r=el.getBoundingClientRect();" +
                    "return{tag:el.tagName.toLowerCase()," +
                    "classes:Array.from(el.classList),visible:r.width>0&&r.height>0};})()"
            try {
                val result = ctx.evaluateJSReturningJSON(js)
                if (result.isNotEmpty()) {
                    val visible = result["visible"] as? Boolean ?: false
                    val matches = state == "attached" || (state == "visible" && visible) || (state == "hidden" && !visible)
                    if (matches) {
                        return successResponse(
                            mapOf(
                                "element" to result,
                                "waitTime" to (System.currentTimeMillis() - start),
                            ),
                        )
                    }
                }
            } catch (_: Exception) {
            }
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
                return successResponse(
                    mapOf(
                        "url" to (result["url"] ?: ""),
                        "title" to (result["title"] ?: ""),
                        "loadTime" to (System.currentTimeMillis() - start),
                    ),
                )
            }
            delay(100)
        }
        return errorResponse("TIMEOUT", "Navigation did not complete within ${timeout}ms")
    }
}
