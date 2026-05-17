package com.kelpie.browser.network

import android.content.Context
import android.util.Log
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
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

private val json =
    Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

/**
 * HTTP server fronting the browser router. The Context parameter must be
 * Application-scoped; this server is started from a long-lived foreground
 * service and an Activity reference here would block GC on config changes.
 */
class HTTPServer(
    private val port: Int,
    private val router: Router,
    appContext: Context,
) {
    companion object {
        /**
         * Maximum request body size accepted by the server (50 MiB).
         * Larger bodies receive `413 Payload Too Large` and the connection is closed.
         * Mirrors iOS and macOS.
         */
        const val MAX_BODY_BYTES: Long = 50L * 1024L * 1024L

        /**
         * Maximum bytes accepted for HTTP request headers before parsing must complete.
         * 64 KiB caps slow-loris pinning while leaving room for cookies and auth headers.
         * Mirrors iOS and macOS.
         */
        const val MAX_HEADER_BYTES: Int = 64 * 1024
    }

    private val appContext: Context = appContext.applicationContext
    private var engine: NettyApplicationEngine? = null
    var isRunning = false
        private set

    fun start() {
        engine =
            embeddedServer(
                factory = Netty,
                port = port,
                configure = {
                    // Cap request line + header bytes at the Netty layer so
                    // oversized headers never make it as far as the routing
                    // pipeline. Netty returns 431 automatically for overflow.
                    maxInitialLineLength = MAX_HEADER_BYTES
                    maxHeaderSize = MAX_HEADER_BYTES
                    maxChunkSize = 64 * 1024
                },
            ) {
                install(ContentNegotiation) { json(json) }

                routing {
                    get("/health") {
                        call.respondText("""{"status":"ok"}""", ContentType.Application.Json)
                    }

                    get("/debug/coordinate-calibration") {
                        val html =
                            appContext.assets.open("diagnostics/coordinate-calibration.html").bufferedReader().use {
                                it.readText()
                            }
                        call.respondText(html, ContentType.Text.Html)
                    }

                    post("/v1/{method}") {
                        // Validate Content-Length BEFORE reading the body to
                        // ensure a single malicious multi-GB POST never gets
                        // buffered. Missing Content-Length on POST is rejected.
                        val contentLengthHeader = call.request.headers[HttpHeaders.ContentLength]
                        val contentLength = contentLengthHeader?.toLongOrNull()
                        if (contentLengthHeader == null) {
                            respondError(
                                call = call,
                                statusCode = HttpStatusCode.LengthRequired,
                                code = "LENGTH_REQUIRED",
                                message = "Content-Length header is required",
                            )
                            return@post
                        }
                        if (contentLength == null || contentLength < 0) {
                            respondError(
                                call = call,
                                statusCode = HttpStatusCode.BadRequest,
                                code = "BAD_REQUEST",
                                message = "Malformed Content-Length",
                            )
                            return@post
                        }
                        if (contentLength > MAX_BODY_BYTES) {
                            respondError(
                                call = call,
                                statusCode = HttpStatusCode.PayloadTooLarge,
                                code = "PAYLOAD_TOO_LARGE",
                                message = "Request body exceeds ${MAX_BODY_BYTES / 1024 / 1024} MB limit",
                            )
                            return@post
                        }

                        val method = call.parameters["method"] ?: ""
                        val bodyText = call.receiveText()
                        // Defense-in-depth: if the client under-declared
                        // Content-Length and streamed more bytes, reject.
                        if (bodyText.toByteArray(Charsets.UTF_8).size.toLong() > MAX_BODY_BYTES) {
                            respondError(
                                call = call,
                                statusCode = HttpStatusCode.PayloadTooLarge,
                                code = "PAYLOAD_TOO_LARGE",
                                message = "Request body exceeds ${MAX_BODY_BYTES / 1024 / 1024} MB limit",
                            )
                            return@post
                        }

                        val body =
                            parseJsonBody(bodyText)
                                ?: return@post call.respondText(
                                    text = mapToJsonString(errorResponse("INVALID_JSON", "Request body is not valid JSON")),
                                    contentType = ContentType.Application.Json,
                                    status = HttpStatusCode.BadRequest,
                                )

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

    private fun parseJsonBody(text: String): Map<String, Any?>? {
        if (text.isEmpty()) return emptyMap()
        return try {
            val element = json.parseToJsonElement(text)
            jsonObjectToMap(element.jsonObject)
        } catch (e: Exception) {
            null
        }
    }

    private fun jsonObjectToMap(obj: JsonObject): Map<String, Any?> = obj.entries.associate { (k, v) -> k to jsonElementToAny(v) }

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
            is kotlinx.serialization.json.JsonArray -> element.map { jsonElementToAny(it) }
        }

    private fun mapToJsonString(map: Map<String, Any?>): String = json.encodeToString(JsonElement.serializer(), mapToJsonElement(map))

    private fun mapToJsonElement(map: Map<String, Any?>): JsonElement = JsonObject(map.entries.associate { (k, v) -> k to anyToJsonElement(v) })

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
            is Map<*, *> -> mapToJsonElement(value as Map<String, Any?>)
            is List<*> -> kotlinx.serialization.json.JsonArray(value.map { anyToJsonElement(it) })
            else -> JsonPrimitive(value.toString())
        }

    private suspend fun respondError(
        call: io.ktor.server.application.ApplicationCall,
        statusCode: HttpStatusCode,
        code: String,
        message: String,
    ) {
        call.respondText(
            text = mapToJsonString(errorResponse(code, message)),
            contentType = ContentType.Application.Json,
            status = statusCode,
        )
    }
}
