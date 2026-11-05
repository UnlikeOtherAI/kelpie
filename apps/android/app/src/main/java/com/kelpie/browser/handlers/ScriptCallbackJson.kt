package com.kelpie.browser.handlers

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/** The WebView callback JSON decoder shared by playback and receipt tests. */
internal object ScriptCallbackJson {
    private val json =
        Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

    fun parseObject(raw: String): Map<String, Any?> {
        val unescaped =
            if (raw.startsWith(34.toChar()) && raw.endsWith(34.toChar())) {
                json.decodeFromString<String>(raw)
            } else {
                raw
            }
        if (unescaped == "null" || unescaped.isBlank()) return emptyMap()
        return try {
            toMap(json.parseToJsonElement(unescaped))
        } catch (_: Exception) {
            emptyMap()
        }
    }

    fun toMap(element: JsonElement): Map<String, Any?> {
        if (element !is JsonObject) return emptyMap()
        return element.entries.associate { (key, value) -> key to toAny(value) }
    }

    private fun toAny(element: JsonElement): Any? =
        when (element) {
            is kotlinx.serialization.json.JsonNull -> null
            is kotlinx.serialization.json.JsonPrimitive ->
                when {
                    element.isString -> element.content
                    element.content == "true" -> true
                    element.content == "false" -> false
                    element.content.contains('.') -> element.content.toDoubleOrNull() ?: element.content
                    else -> element.content.toIntOrNull() ?: element.content.toLongOrNull() ?: element.content
                }
            is JsonObject -> element.entries.associate { (key, value) -> key to toAny(value) }
            is kotlinx.serialization.json.JsonArray -> element.map { toAny(it) }
        }
}
