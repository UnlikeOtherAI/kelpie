package com.kelpie.browser.network

import android.util.Log
import io.ktor.http.ContentType
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.call
import io.ktor.server.application.install
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.netty.NettyApplicationEngine
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.request.receiveText
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.routing
import kotlinx.serialization.json.Json
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
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

private val json = Json { ignoreUnknownKeys = true; isLenient = true }

class HTTPServer(
    private val port: Int,
    private val router: Router,
) {
    private var engine: NettyApplicationEngine? = null
    var isRunning = false
        private set

    fun start() {
        engine = embeddedServer(Netty, port = port) {
            install(ContentNegotiation) { json(json) }

            routing {
                get("/health") {
                    call.respondText("""{"status":"ok"}""", ContentType.Application.Json)
                }

                post("/v1/{method}") {
                    val method = call.parameters["method"] ?: ""
                    val bodyText = call.receiveText()
                    val body = parseJsonBody(bodyText)

                    val (status, result) = router.handle(method, body)
                    val responseJson = mapToJsonString(result)

                    call.respondText(
                        text = responseJson,
                        contentType = ContentType.Application.Json,
                        status = HttpStatusCode.fromValue(status),
                    )
                }
            }
        }.also {
            it.start(wait = false)
            isRunning = true
            Log.i("HTTPServer", "Started on port $port")
        }
    }

    fun stop() {
        engine?.stop(1000, 2000)
        engine = null
        isRunning = false
    }

    private fun parseJsonBody(text: String): Map<String, Any?> {
        if (text.isBlank()) return emptyMap()
        return try {
            val element = json.parseToJsonElement(text)
            jsonObjectToMap(element.jsonObject)
        } catch (e: Exception) {
            emptyMap()
        }
    }

    private fun jsonObjectToMap(obj: JsonObject): Map<String, Any?> =
        obj.entries.associate { (k, v) -> k to jsonElementToAny(v) }

    private fun jsonElementToAny(element: JsonElement): Any? = when (element) {
        is JsonNull -> null
        is JsonPrimitive -> when {
            element.isString -> element.content
            element.booleanOrNull != null -> element.boolean
            element.intOrNull != null -> element.int
            element.doubleOrNull != null -> element.double
            else -> element.content
        }
        is JsonObject -> jsonObjectToMap(element)
        is kotlinx.serialization.json.JsonArray -> element.map { jsonElementToAny(it) }
    }

    private fun mapToJsonString(map: Map<String, Any?>): String {
        return json.encodeToString(JsonElement.serializer(), mapToJsonElement(map))
    }

    private fun mapToJsonElement(map: Map<String, Any?>): JsonElement {
        return JsonObject(map.entries.associate { (k, v) -> k to anyToJsonElement(v) })
    }

    @Suppress("UNCHECKED_CAST")
    private fun anyToJsonElement(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is Boolean -> JsonPrimitive(value)
        is Int -> JsonPrimitive(value)
        is Long -> JsonPrimitive(value)
        is Double -> JsonPrimitive(value)
        is Float -> JsonPrimitive(value)
        is String -> JsonPrimitive(value)
        is Map<*, *> -> mapToJsonElement(value as Map<String, Any?>)
        is List<*> -> kotlinx.serialization.json.JsonArray(value.map { anyToJsonElement(it) })
        else -> JsonPrimitive(value.toString())
    }
}
