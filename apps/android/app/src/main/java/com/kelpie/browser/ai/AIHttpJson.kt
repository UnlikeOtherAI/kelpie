package com.kelpie.browser.ai

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

private val aiJson =
    Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

/** Plain JSON-over-HTTP helpers used by the Ollama backend and the model catalog bridge. */
internal object AIHttpJson {
    suspend fun getJson(url: String): Map<String, Any?> =
        withContext(Dispatchers.IO) {
            val connection =
                (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 3_000
                    readTimeout = 10_000
                    doInput = true
                }

            try {
                val body = readConnectionBody(connection)
                if (connection.responseCode !in 200..299) {
                    throw IOException("HTTP ${connection.responseCode}: $body")
                }
                parseJsonObject(body)
            } finally {
                connection.disconnect()
            }
        }

    suspend fun postJson(
        url: String,
        payload: Map<String, Any?>,
    ): Map<String, Any?> =
        withContext(Dispatchers.IO) {
            val connection =
                (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 3_000
                    readTimeout = 30_000
                    doInput = true
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Accept", "application/json")
                }

            try {
                connection.outputStream.bufferedWriter().use { writer ->
                    writer.write(mapToJsonString(payload))
                }

                val body = readConnectionBody(connection)
                if (connection.responseCode !in 200..299) {
                    throw IOException("HTTP ${connection.responseCode}: $body")
                }
                parseJsonObject(body)
            } finally {
                connection.disconnect()
            }
        }

    private fun readConnectionBody(connection: HttpURLConnection): String {
        val stream =
            if (connection.responseCode in 200..299) {
                connection.inputStream
            } else {
                connection.errorStream
            } ?: return ""

        return stream.bufferedReader().use { it.readText() }
    }

    private fun mapToJsonString(map: Map<String, Any?>): String = aiJson.encodeToString(JsonElement.serializer(), mapToJsonObject(map))

    private fun mapToJsonObject(map: Map<String, Any?>): JsonObject = JsonObject(map.entries.associate { (key, value) -> key to anyToJsonElement(value) })

    @Suppress("UNCHECKED_CAST")
    private fun anyToJsonElement(value: Any?): JsonElement =
        when (value) {
            null -> JsonNull
            is Boolean -> JsonPrimitive(value)
            is Int -> JsonPrimitive(value)
            is Long -> JsonPrimitive(value)
            is Double -> JsonPrimitive(value)
            is Float -> JsonPrimitive(value)
            is String -> JsonPrimitive(value)
            is Map<*, *> -> mapToJsonObject(value as Map<String, Any?>)
            is List<*> -> JsonArray(value.map { anyToJsonElement(it) })
            else -> JsonPrimitive(value.toString())
        }

    fun parseJsonObject(text: String): Map<String, Any?> {
        if (text.isBlank()) return emptyMap()
        val element = aiJson.parseToJsonElement(text)
        return jsonObjectToMap(element.jsonObject)
    }

    fun parseJsonArray(text: String): List<Any?> {
        if (text.isBlank()) return emptyList()
        return aiJson.parseToJsonElement(text).jsonArray.map { jsonElementToAny(it) }
    }

    private fun jsonObjectToMap(obj: JsonObject): Map<String, Any?> = obj.entries.associate { (key, value) -> key to jsonElementToAny(value) }

    private fun jsonElementToAny(element: JsonElement): Any? =
        when (element) {
            is JsonNull -> null
            is JsonPrimitive ->
                when {
                    element.isString -> element.content
                    element.booleanOrNull != null -> element.boolean
                    element.intOrNull != null -> element.int
                    element.doubleOrNull != null -> element.double
                    else -> element.content
                }
            is JsonObject -> jsonObjectToMap(element)
            is JsonArray -> element.map { jsonElementToAny(it) }
        }
}
