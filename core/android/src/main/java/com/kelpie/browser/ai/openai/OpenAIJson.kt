package com.kelpie.browser.ai.openai

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull

/**
 * Small, tolerant JSON helpers for the OpenAI-compatible client. Servers differ wildly,
 * so every accessor returns null instead of throwing on an unexpected shape.
 */
object OpenAIJson {
    val json =
        Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

    fun parseOrNull(text: String): JsonElement? =
        try {
            json.parseToJsonElement(text)
        } catch (_: Exception) {
            null
        }

    fun parseObjectOrNull(text: String): JsonObject? = parseOrNull(text) as? JsonObject

    fun objectOrNull(element: JsonElement?): JsonObject? = element as? JsonObject

    fun arrayOrNull(element: JsonElement?): JsonArray? = element as? JsonArray

    fun string(element: JsonElement?): String? {
        val primitive = element as? JsonPrimitive ?: return null
        return if (primitive.isString) primitive.content else null
    }

    fun int(element: JsonElement?): Int? {
        val primitive = element as? JsonPrimitive ?: return null
        if (primitive.isString) return primitive.content.trim().toIntOrNull()
        return primitive.intOrNull ?: primitive.doubleOrNull?.takeIf { it % 1.0 == 0.0 }?.toInt()
    }

    fun boolean(element: JsonElement?): Boolean? {
        val primitive = element as? JsonPrimitive ?: return null
        if (primitive.isString) return null
        return primitive.booleanOrNull
    }

    fun encode(element: JsonElement): String = json.encodeToString(JsonElement.serializer(), element)

    /** Converts a router-style `Map<String, Any?>` value tree into JSON. */
    @Suppress("UNCHECKED_CAST")
    fun fromAny(value: Any?): JsonElement =
        when (value) {
            null -> JsonNull
            is JsonElement -> value
            is Boolean -> JsonPrimitive(value)
            is Number -> JsonPrimitive(value)
            is String -> JsonPrimitive(value)
            is Map<*, *> -> JsonObject((value as Map<String, Any?>).mapValues { fromAny(it.value) })
            is List<*> -> JsonArray(value.map { fromAny(it) })
            is Array<*> -> JsonArray(value.map { fromAny(it) })
            else -> JsonPrimitive(value.toString())
        }

    /** Converts JSON into the router's `Map<String, Any?>` value tree (ints stay Int when they fit). */
    fun toAny(element: JsonElement?): Any? =
        when (element) {
            null, is JsonNull -> null
            is JsonPrimitive ->
                when {
                    element.isString -> element.content
                    element.booleanOrNull != null -> element.booleanOrNull
                    element.intOrNull != null -> element.intOrNull
                    element.longOrNull != null -> element.longOrNull
                    element.doubleOrNull != null -> element.doubleOrNull
                    else -> element.content
                }
            is JsonObject -> element.mapValues { toAny(it.value) }
            is JsonArray -> element.map { toAny(it) }
        }

    @Suppress("UNCHECKED_CAST")
    fun toMap(element: JsonObject): Map<String, Any?> = toAny(element) as Map<String, Any?>
}
