package com.kelpie.browser.sync

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull

/** A sync failure with a stable code. Messages never carry cookie data, tickets or keys. */
class SyncFailure(
    val code: String,
    message: String = code,
) : Exception(message)

internal object SyncJson {
    private val parser = Json { ignoreUnknownKeys = true }

    /** Parses a core-sync result, turning its `{"error"}` shape into a [SyncFailure]. */
    fun native(text: String?): JsonObject {
        val value =
            text?.let { runCatching { parser.parseToJsonElement(it) }.getOrNull() } as? JsonObject
                ?: throw SyncFailure("INTERNAL", "core-sync returned no object")
        val error = value.string("error")
        if (error != null && value.size <= 2 && (value.size == 1 || value.containsKey("message"))) {
            throw SyncFailure(error, value.string("message") ?: error)
        }
        return value
    }

    fun parseObject(text: String): JsonObject? = runCatching { parser.parseToJsonElement(text) as? JsonObject }.getOrNull()
}

internal fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull

internal fun JsonObject.long(key: String): Long? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull

internal fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull

internal fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject

internal fun JsonObject.array(key: String): JsonArray? = this[key] as? JsonArray

/** Converts handler maps (HTTP layer) to JSON and back. */
internal object SyncMaps {
    fun toJson(value: Any?): JsonElement =
        when (value) {
            null -> JsonNull
            is JsonElement -> value
            is Boolean -> JsonPrimitive(value)
            is Number -> JsonPrimitive(value)
            is String -> JsonPrimitive(value)
            is Map<*, *> -> JsonObject(value.entries.associate { (k, v) -> k.toString() to toJson(v) })
            is List<*> -> JsonArray(value.map(::toJson))
            else -> JsonPrimitive(value.toString())
        }

    fun fromJson(element: JsonElement?): Any? =
        when (element) {
            null, JsonNull -> null
            is JsonObject -> element.entries.associate { (k, v) -> k to fromJson(v) }
            is JsonArray -> element.map(::fromJson)
            is JsonPrimitive ->
                when {
                    element.isString -> element.content
                    element.booleanOrNull != null -> element.booleanOrNull
                    element.longOrNull != null -> element.longOrNull
                    else -> element.content.toDoubleOrNull() ?: element.content
                }
        }
}
