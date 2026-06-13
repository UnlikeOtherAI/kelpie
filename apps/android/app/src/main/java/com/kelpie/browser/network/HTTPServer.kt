package com.kelpie.browser.network

import android.content.Context
import android.util.Log
import com.kelpie.browser.device.DeviceInfo
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.call
import io.ktor.server.application.install
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.netty.NettyApplicationEngine
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.plugins.origin
import io.ktor.server.request.httpMethod
import io.ktor.server.request.receiveText
import io.ktor.server.request.uri
import io.ktor.server.response.header
import io.ktor.server.response.respondText
import io.ktor.server.routing.delete
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import io.ktor.server.routing.routing
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
import kotlinx.serialization.json.jsonObject
import java.net.URLDecoder

private val json =
    Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

/**
 * Embedded HTTP server for receiving CLI commands.
 *
 * All v1 routes (except the unauth allowlist enforced by [AuthMiddleware])
 * require a bearer token issued by the pairing flow. CORS headers are not
 * emitted — CLI fetch is not a browser.
 *
 * The Context parameter must be Application-scoped; this server is started
 * from a long-lived foreground service and an Activity reference here would
 * block GC on config changes.
 */
class HTTPServer(
    private val port: Int,
    private val router: Router,
    appContext: Context,
    private val pairingStore: PairingStore,
    private val deviceInfo: DeviceInfo,
    private val onPendingPairChanged: () -> Unit,
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
        val middleware = AuthMiddleware(pairingStore)
        val pairEndpoints =
            PairEndpoints(pairingStore) { onPendingPairChanged() }

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
                    // --- Health (unauth) ---
                    get("/health") {
                        call.respondText("""{"status":"ok"}""", ContentType.Application.Json)
                    }

                    // --- Debug page (authenticated) ---
                    get("/debug/coordinate-calibration") {
                        val parsed = parsedRequest(call)
                        when (val decision = middleware.evaluate(parsed)) {
                            is AuthDecision.Reject -> respondReject(call, decision)
                            AuthDecision.Unauthenticated ->
                                respondReject(
                                    call,
                                    AuthDecision.Reject(401, "UNAUTHORIZED", "Authentication required"),
                                )
                            is AuthDecision.Authenticated -> {
                                val html =
                                    appContext.assets.open("diagnostics/coordinate-calibration.html").bufferedReader().use {
                                        it.readText()
                                    }
                                call.respondText(html, ContentType.Text.Html)
                            }
                        }
                    }

                    route("/v1") {
                        // --- Pairing endpoints (unauth + CSRF-gated POST) ---
                        post("/pair") {
                            val parsed = parsedRequest(call)
                            when (val decision = middleware.evaluate(parsed)) {
                                is AuthDecision.Reject -> respondReject(call, decision)
                                AuthDecision.Unauthenticated -> {
                                    val bodyText = call.receiveText()
                                    val result = pairEndpoints.handlePairPost(bodyText, parsed.sourceAddress)
                                    respondPairing(call, result.status, result.json, noStore = true)
                                }
                                is AuthDecision.Authenticated -> {
                                    // The unauth allowlist sends pair endpoints through
                                    // the Unauthenticated branch; an authenticated client
                                    // hitting POST /v1/pair gets the same handling so
                                    // there is no special-casing — fall through to the
                                    // unauth path.
                                    val bodyText = call.receiveText()
                                    val result = pairEndpoints.handlePairPost(bodyText, parsed.sourceAddress)
                                    respondPairing(call, result.status, result.json, noStore = true)
                                }
                            }
                        }
                        get("/pair/status") {
                            val parsed = parsedRequest(call)
                            when (val decision = middleware.evaluate(parsed)) {
                                is AuthDecision.Reject -> respondReject(call, decision)
                                else -> {
                                    val requestId = call.request.queryParameters["requestId"]
                                    val result = pairEndpoints.handlePairStatus(requestId, parsed.sourceAddress)
                                    respondPairing(call, result.status, result.json, noStore = true)
                                }
                            }
                        }
                        delete("/pair") {
                            val parsed = parsedRequest(call)
                            when (val decision = middleware.evaluate(parsed)) {
                                is AuthDecision.Reject -> respondReject(call, decision)
                                AuthDecision.Unauthenticated ->
                                    respondReject(
                                        call,
                                        AuthDecision.Reject(401, "UNAUTHORIZED", "Authentication required"),
                                    )
                                is AuthDecision.Authenticated -> {
                                    val result = pairEndpoints.handlePairDelete(decision.clientId)
                                    respondPairing(call, result.status, result.json, noStore = true)
                                }
                            }
                        }
                        get("/get-device-info") {
                            val parsed = parsedRequest(call)
                            when (val decision = middleware.evaluate(parsed)) {
                                is AuthDecision.Reject -> respondReject(call, decision)
                                else -> {
                                    val result =
                                        pairEndpoints.handleGetDeviceInfo(
                                            deviceInfo.name,
                                            "android",
                                            deviceInfo.version,
                                        )
                                    respondPairing(call, result.status, result.json, noStore = false)
                                }
                            }
                        }

                        // --- Generic authenticated POST /v1/{method} ---
                        post("/{method}") {
                            val parsed = parsedRequest(call)
                            when (val decision = middleware.evaluate(parsed)) {
                                is AuthDecision.Reject -> respondReject(call, decision)
                                AuthDecision.Unauthenticated ->
                                    respondReject(
                                        call,
                                        AuthDecision.Reject(401, "UNAUTHORIZED", "Authentication required"),
                                    )
                                is AuthDecision.Authenticated -> handleAuthenticatedPost(call)
                            }
                        }
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

    private suspend fun handleAuthenticatedPost(call: ApplicationCall) {
        // Validate Content-Length BEFORE reading the body to ensure a single
        // malicious multi-GB POST never gets buffered. Missing Content-Length
        // on POST is rejected.
        val contentLengthHeader = call.request.headers[HttpHeaders.ContentLength]
        val contentLength = contentLengthHeader?.toLongOrNull()
        if (contentLengthHeader == null) {
            respondError(
                call = call,
                statusCode = HttpStatusCode.LengthRequired,
                code = "LENGTH_REQUIRED",
                message = "Content-Length header is required",
            )
            return
        }
        if (contentLength == null || contentLength < 0) {
            respondError(
                call = call,
                statusCode = HttpStatusCode.BadRequest,
                code = "BAD_REQUEST",
                message = "Malformed Content-Length",
            )
            return
        }
        if (contentLength > MAX_BODY_BYTES) {
            respondError(
                call = call,
                statusCode = HttpStatusCode.PayloadTooLarge,
                code = "PAYLOAD_TOO_LARGE",
                message = "Request body exceeds ${MAX_BODY_BYTES / 1024 / 1024} MB limit",
            )
            return
        }

        val method = call.parameters["method"] ?: ""
        val bodyText = call.receiveText()
        // Defense-in-depth: if the client under-declared Content-Length and
        // streamed more bytes, reject.
        if (bodyText.toByteArray(Charsets.UTF_8).size.toLong() > MAX_BODY_BYTES) {
            respondError(
                call = call,
                statusCode = HttpStatusCode.PayloadTooLarge,
                code = "PAYLOAD_TOO_LARGE",
                message = "Request body exceeds ${MAX_BODY_BYTES / 1024 / 1024} MB limit",
            )
            return
        }

        val body = parseJsonBody(bodyText)
        if (body == null) {
            call.respondText(
                text = mapToJsonString(errorResponse("INVALID_JSON", "Request body is not valid JSON")),
                contentType = ContentType.Application.Json,
                status = HttpStatusCode.BadRequest,
            )
            return
        }
        val (status, result) = router.handle(method, body)
        call.respondText(
            text = mapToJsonString(result),
            contentType = ContentType.Application.Json,
            status = HttpStatusCode.fromValue(status),
        )
    }

    private fun parsedRequest(call: ApplicationCall): ParsedRequest {
        val rawPath = call.request.uri.substringBefore('?')
        val decodedPath = runCatching { URLDecoder.decode(rawPath, Charsets.UTF_8.name()) }.getOrDefault(rawPath)
        val headers: MutableMap<String, MutableList<String>> = mutableMapOf()
        var hasTransferEncoding = false
        for (name in call.request.headers.names()) {
            val key = name.lowercase()
            val values = call.request.headers.getAll(name) ?: continue
            headers[key] = values.toMutableList()
            if (key == "transfer-encoding") hasTransferEncoding = true
        }
        // Best-effort source address: Ktor exposes the local peer via request.origin.
        val sourceAddress = call.request.origin.remoteHost
        return ParsedRequest(
            method = call.request.httpMethod.value,
            path = decodedPath,
            headers = headers,
            hasTransferEncoding = hasTransferEncoding,
            sourceAddress = sourceAddress,
        )
    }

    private suspend fun respondReject(
        call: ApplicationCall,
        reject: AuthDecision.Reject,
    ) {
        val payload =
            mapOf(
                "success" to false,
                "error" to mapOf("code" to reject.errorCode, "message" to reject.message),
            )
        call.respondText(
            text = mapToJsonString(payload),
            contentType = ContentType.Application.Json,
            status = HttpStatusCode.fromValue(reject.status),
        )
    }

    private suspend fun respondPairing(
        call: ApplicationCall,
        status: Int,
        body: Map<String, Any?>,
        noStore: Boolean,
    ) {
        if (noStore) {
            call.response.header("Cache-Control", "no-store, no-cache")
            call.response.header("Pragma", "no-cache")
        }
        call.respondText(
            text = mapToJsonString(body),
            contentType = ContentType.Application.Json,
            status = HttpStatusCode.fromValue(status),
        )
    }

    private suspend fun respondError(
        call: ApplicationCall,
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

    private fun parseJsonBody(text: String): Map<String, Any?>? {
        if (text.isEmpty()) return emptyMap()
        return try {
            val element = json.parseToJsonElement(text)
            jsonObjectToMap(element.jsonObject)
        } catch (_: Exception) {
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
            is JsonArray -> element.map { jsonElementToAny(it) }
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
            is List<*> -> JsonArray(value.map { anyToJsonElement(it) })
            else -> JsonPrimitive(value.toString())
        }

    private fun errorResponse(
        code: String,
        message: String,
    ): Map<String, Any?> =
        mapOf(
            "success" to false,
            "error" to mapOf("code" to code, "message" to message),
        )
}
