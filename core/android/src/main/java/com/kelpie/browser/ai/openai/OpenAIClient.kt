package com.kelpie.browser.ai.openai

import kotlinx.serialization.json.JsonObject
import java.io.ByteArrayOutputStream

/**
 * Speaks the OpenAI-compatible HTTP protocol (`GET /models`, `POST /chat/completions`)
 * over an injected [OpenAITransport]. Holds no state; the API key is passed per call
 * and only ever placed in the `Authorization` header.
 */
class OpenAIClient(
    private val transport: OpenAITransport,
) {
    suspend fun listModels(
        base: OpenAIEndpointURL,
        apiKey: String?,
    ): List<DiscoveredModel> {
        val body = ByteArrayOutputStream()
        val response =
            transport.execute(
                TransportRequest("GET", base.join("models"), headers(apiKey, ACCEPT_JSON), null, TransportTimeouts.PROBE),
            ) { bytes, length -> appendBounded(body, bytes, length) }
        if (!response.isSuccess) throw discoveryError(response, apiKey)
        return ModelsParser.parse(body.toString(Charsets.UTF_8.name()))
    }

    /**
     * Sends a chat completion. With [stream] the response is parsed as SSE (falling back to a
     * plain JSON body when a server ignores `stream: true`). [onProgress] fires for every chunk.
     */
    suspend fun chat(
        base: OpenAIEndpointURL,
        apiKey: String?,
        payload: JsonObject,
        stream: Boolean,
        onProgress: () -> Unit = {},
    ): ChatResult {
        val reader = ChatBodyReader(apiKey, stream)
        val response =
            transport.execute(
                TransportRequest(
                    "POST",
                    base.join("chat/completions"),
                    headers(apiKey, if (stream) ACCEPT_SSE else ACCEPT_JSON) + (CONTENT_TYPE to JSON_MEDIA_TYPE),
                    OpenAIJson.encode(payload).toByteArray(Charsets.UTF_8),
                    TransportTimeouts.CHAT,
                ),
            ) { bytes, length ->
                reader.feed(bytes, length)
                onProgress()
            }
        if (!response.isSuccess) throw chatError(response, apiKey, payload.containsKey("tools"))
        return reader.finish(response.contentType)
    }

    private fun headers(
        apiKey: String?,
        accept: String,
    ): Map<String, String> {
        val headers = linkedMapOf("Accept" to accept)
        if (!apiKey.isNullOrEmpty()) headers["Authorization"] = "Bearer $apiKey"
        return headers
    }

    private fun appendBounded(
        out: ByteArrayOutputStream,
        bytes: ByteArray,
        length: Int,
    ) {
        if (out.size() + length > MAX_MODELS_BYTES) {
            throw OpenAIException(OpenAIErrorCode.ENDPOINT_MALFORMED_RESPONSE, "The /models response is too large")
        }
        out.write(bytes, 0, length)
    }

    companion object {
        const val ACCEPT_JSON = "application/json"
        const val ACCEPT_SSE = "text/event-stream"
        const val CONTENT_TYPE = "Content-Type"
        const val JSON_MEDIA_TYPE = "application/json"
        private const val MAX_MODELS_BYTES = 4 * 1024 * 1024

        fun discoveryError(
            response: TransportResponse,
            apiKey: String?,
        ): OpenAIException {
            val message = ServerErrorText.sanitize(response.errorBody.orEmpty(), apiKey)
            val code =
                when (response.status) {
                    401, 403 -> OpenAIErrorCode.ENDPOINT_AUTH_FAILED
                    404, 405, 501 -> OpenAIErrorCode.MODEL_DISCOVERY_UNSUPPORTED
                    503 -> OpenAIErrorCode.ENDPOINT_LOADING
                    else -> OpenAIErrorCode.ENDPOINT_ERROR
                }
            return OpenAIException(code, describe(response.status, message), httpStatus = response.status)
        }

        fun chatError(
            response: TransportResponse,
            apiKey: String?,
            sentTools: Boolean,
        ): OpenAIException {
            val message = ServerErrorText.sanitize(response.errorBody.orEmpty(), apiKey)
            val lower = message.lowercase()
            val code =
                when {
                    response.status == 401 || response.status == 403 -> OpenAIErrorCode.ENDPOINT_AUTH_FAILED
                    response.status == 503 -> OpenAIErrorCode.ENDPOINT_LOADING
                    response.status == 404 && lower.contains("model") -> OpenAIErrorCode.MODEL_NOT_AVAILABLE
                    sentTools && response.status in 400..499 && lower.contains("tool") -> OpenAIErrorCode.TOOLS_NOT_SUPPORTED
                    else -> OpenAIErrorCode.ENDPOINT_ERROR
                }
            return OpenAIException(code, describe(response.status, message), httpStatus = response.status)
        }

        private fun describe(
            status: Int,
            message: String,
        ): String = if (message.isEmpty()) "HTTP $status" else "HTTP $status: $message"
    }
}

/** Buffers or streams a chat response body depending on what the server actually sent. */
private class ChatBodyReader(
    apiKey: String?,
    private val expectStream: Boolean,
) {
    private val accumulator = ChatAccumulator(apiKey)
    private val raw = ByteArrayOutputStream()
    private var mode: Mode? = null
    private val sse = SSEParser(onEvent = { event -> if (!accumulator.sawDone) accumulator.consume(event.data) })

    fun feed(
        bytes: ByteArray,
        length: Int,
    ) {
        val current = mode ?: detect(bytes, length) ?: return raw.write(bytes, 0, length)
        mode = current
        if (current == Mode.SSE) {
            if (raw.size() > 0) {
                val buffered = raw.toByteArray()
                raw.reset()
                sse.feed(buffered)
            }
            sse.feed(bytes, length)
        } else {
            if (raw.size() + length > MAX_JSON_BYTES) {
                throw OpenAIException(OpenAIErrorCode.ENDPOINT_MALFORMED_RESPONSE, "The response is too large")
            }
            raw.write(bytes, 0, length)
        }
    }

    fun finish(contentType: String?): ChatResult {
        val resolved = mode ?: if (contentType?.contains("event-stream") == true) Mode.SSE else Mode.JSON
        if (resolved == Mode.SSE) {
            if (raw.size() > 0) sse.feed(raw.toByteArray())
            sse.finish()
            return accumulator.finish()
        }
        return accumulator.consumeCompleteResponse(raw.toString(Charsets.UTF_8.name()))
    }

    /** First non-whitespace byte: `{` → JSON body, anything else → SSE (when streaming). */
    private fun detect(
        bytes: ByteArray,
        length: Int,
    ): Mode? {
        val all = raw.toByteArray() + bytes.copyOf(length)
        val first = all.firstOrNull { !it.toInt().toChar().isWhitespace() } ?: return null
        return when {
            first == '{'.code.toByte() -> Mode.JSON
            expectStream -> Mode.SSE
            else -> Mode.JSON
        }
    }

    private enum class Mode { SSE, JSON }

    private companion object {
        const val MAX_JSON_BYTES = 16 * 1024 * 1024
    }
}
