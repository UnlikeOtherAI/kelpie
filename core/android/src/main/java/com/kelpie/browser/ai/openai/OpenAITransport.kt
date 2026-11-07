package com.kelpie.browser.ai.openai

import java.net.URI

/**
 * Timeouts for one request. [readMs] bounds both time-to-first-byte and the idle gap
 * between packets (any bytes, including `: keep-alive` comments, reset it).
 */
data class TransportTimeouts(
    val connectMs: Int,
    val readMs: Int,
    val totalMs: Long,
) {
    companion object {
        /** Probe and model discovery: 8 s for everything. */
        val PROBE = TransportTimeouts(connectMs = 8_000, readMs = 8_000, totalMs = 8_000)

        /** Chat: 180 s to first byte and between packets, 900 s overall. */
        val CHAT = TransportTimeouts(connectMs = 15_000, readMs = 180_000, totalMs = 900_000)
    }
}

class TransportRequest(
    val method: String,
    val url: String,
    val headers: Map<String, String>,
    val body: ByteArray?,
    val timeouts: TransportTimeouts,
)

/** [errorBody] is set (bounded) for non-2xx responses; 2xx bodies are streamed to the sink instead. */
data class TransportResponse(
    val status: Int,
    val contentType: String?,
    val errorBody: String?,
) {
    val isSuccess: Boolean get() = status in 200..299
}

/**
 * Abstract HTTP transport so tests can inject fakes. Implementations must throw
 * [OpenAIException] with `ENDPOINT_UNREACHABLE`, `ENDPOINT_TIMEOUT` or
 * `ENDPOINT_REDIRECT_REFUSED`, and abort the connection when the coroutine is cancelled.
 */
interface OpenAITransport {
    suspend fun execute(
        request: TransportRequest,
        onBody: (ByteArray, Int) -> Unit,
    ): TransportResponse
}

/** Same-origin redirect policy: credentials are never forwarded to another origin. */
object RedirectPolicy {
    const val MAX_REDIRECTS = 5

    /** Resolves [location] against [current]; returns null when the target is cross-origin. */
    fun resolveSameOrigin(
        current: String,
        location: String,
    ): String? {
        val base = runCatching { URI(current) }.getOrNull() ?: return null
        val target = runCatching { base.resolve(location.trim()) }.getOrNull() ?: return null
        return if (origin(base) != null && origin(base) == origin(target)) target.toString() else null
    }

    private fun origin(uri: URI): Triple<String, String, Int>? {
        val scheme = uri.scheme?.lowercase() ?: return null
        val host =
            uri.host
                ?.lowercase()
                ?.removePrefix("[")
                ?.removeSuffix("]") ?: return null
        val port =
            when {
                uri.port != -1 -> uri.port
                scheme == "https" -> 443
                scheme == "http" -> 80
                else -> return null
            }
        return Triple(scheme, host, port)
    }
}
