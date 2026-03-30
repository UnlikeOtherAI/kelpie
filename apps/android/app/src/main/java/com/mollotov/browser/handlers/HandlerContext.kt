package com.mollotov.browser.handlers

import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.jsonObject

private val json = Json { ignoreUnknownKeys = true; isLenient = true }
private val mainHandler = Handler(Looper.getMainLooper())

class HandlerContext {
    var webView: WebView? = null

    suspend fun evaluateJS(script: String): String = suspendCoroutine { cont ->
        val wv = webView
        if (wv == null) {
            cont.resumeWithException(IllegalStateException("No WebView"))
            return@suspendCoroutine
        }
        mainHandler.post {
            wv.evaluateJavascript(script) { result ->
                cont.resume(result ?: "null")
            }
        }
    }

    suspend fun evaluateJSReturningJSON(script: String): Map<String, Any?> {
        val wrapped = "JSON.stringify(($script))"
        val raw = evaluateJS(wrapped)
        // WebView returns a JSON-encoded string (escaped), so we need to unescape
        val unescaped = if (raw.startsWith("\"") && raw.endsWith("\"")) {
            json.decodeFromString<String>(raw)
        } else {
            raw
        }
        if (unescaped == "null" || unescaped.isBlank()) return emptyMap()
        return try {
            val element = json.parseToJsonElement(unescaped)
            jsonElementToMap(element)
        } catch (_: Exception) {
            emptyMap()
        }
    }

    suspend fun evaluateJSReturningArray(script: String): List<Map<String, Any?>> {
        val wrapped = "JSON.stringify(($script))"
        val raw = evaluateJS(wrapped)
        val unescaped = if (raw.startsWith("\"") && raw.endsWith("\"")) {
            json.decodeFromString<String>(raw)
        } else {
            raw
        }
        if (unescaped == "null" || unescaped.isBlank()) return emptyList()
        return try {
            val element = json.parseToJsonElement(unescaped)
            if (element is kotlinx.serialization.json.JsonArray) {
                element.map { jsonElementToMap(it) }
            } else {
                emptyList()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun jsonElementToMap(element: JsonElement): Map<String, Any?> {
        if (element !is kotlinx.serialization.json.JsonObject) return emptyMap()
        return element.jsonObject.entries.associate { (k, v) -> k to jsonElementToAny(v) }
    }

    private fun jsonElementToAny(element: JsonElement): Any? = when (element) {
        is kotlinx.serialization.json.JsonNull -> null
        is kotlinx.serialization.json.JsonPrimitive -> {
            when {
                element.isString -> element.content
                element.content == "true" -> true
                element.content == "false" -> false
                element.content.contains('.') -> element.content.toDoubleOrNull() ?: element.content
                else -> element.content.toIntOrNull() ?: element.content.toLongOrNull() ?: element.content
            }
        }
        is kotlinx.serialization.json.JsonObject -> element.entries.associate { (k, v) -> k to jsonElementToAny(v) }
        is kotlinx.serialization.json.JsonArray -> element.map { jsonElementToAny(it) }
    }
}
