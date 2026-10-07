package com.kelpie.browser.ai.openai

/** Error codes shared with macOS, iOS and the CLI (see docs/plans/2026-10-07-openai-compatible-endpoints.md). */
object OpenAIErrorCode {
    const val INVALID_ENDPOINT_URL = "INVALID_ENDPOINT_URL"
    const val ENDPOINT_NOT_FOUND = "ENDPOINT_NOT_FOUND"
    const val ENDPOINT_UNREACHABLE = "ENDPOINT_UNREACHABLE"
    const val ENDPOINT_AUTH_FAILED = "ENDPOINT_AUTH_FAILED"
    const val ENDPOINT_LOADING = "ENDPOINT_LOADING"
    const val ENDPOINT_REDIRECT_REFUSED = "ENDPOINT_REDIRECT_REFUSED"
    const val ENDPOINT_MALFORMED_RESPONSE = "ENDPOINT_MALFORMED_RESPONSE"
    const val ENDPOINT_STREAM_TRUNCATED = "ENDPOINT_STREAM_TRUNCATED"
    const val ENDPOINT_TIMEOUT = "ENDPOINT_TIMEOUT"
    const val ENDPOINT_ERROR = "ENDPOINT_ERROR"
    const val MODEL_DISCOVERY_UNSUPPORTED = "MODEL_DISCOVERY_UNSUPPORTED"
    const val MODEL_NOT_AVAILABLE = "MODEL_NOT_AVAILABLE"
    const val NO_MODEL_SELECTED = "NO_MODEL_SELECTED"
    const val TOOLS_UNVERIFIED = "TOOLS_UNVERIFIED"
    const val TOOLS_NOT_SUPPORTED = "TOOLS_NOT_SUPPORTED"
    const val VISION_NOT_SUPPORTED = "VISION_NOT_SUPPORTED"
    const val AGENT_STEP_LIMIT = "AGENT_STEP_LIMIT"
    const val INFERENCE_CANCELLED = "INFERENCE_CANCELLED"
}

/**
 * A failure with a contract error code. [httpStatus] is kept for health evaluation
 * (429 / 503 → busy or loading) and never shown on its own.
 */
class OpenAIException(
    val code: String,
    override val message: String,
    val httpStatus: Int? = null,
    val diagnostics: Map<String, Any?>? = null,
) : Exception(message)

/** Server error text handling: redact the API key, then cap the length. */
object ServerErrorText {
    const val MAX_LENGTH = 300
    private const val REDACTED = "[redacted]"

    fun sanitize(
        raw: String,
        apiKey: String?,
    ): String {
        var text = extractMessage(raw)
        if (!apiKey.isNullOrEmpty()) {
            text = text.replace(apiKey, REDACTED)
        }
        text = text.replace(Regex("\\s+"), " ").trim()
        return if (text.length <= MAX_LENGTH) text else text.substring(0, MAX_LENGTH - 1) + "…"
    }

    /** Prefer `error.message`, `error` (string), `message` or `detail` from a JSON body; otherwise the raw text. */
    private fun extractMessage(raw: String): String {
        val obj = OpenAIJson.parseObjectOrNull(raw) ?: return raw
        val error = obj["error"]
        OpenAIJson.string(OpenAIJson.objectOrNull(error)?.get("message"))?.let { return it }
        OpenAIJson.string(error)?.let { return it }
        OpenAIJson.string(obj["message"])?.let { return it }
        OpenAIJson.string(obj["detail"])?.let { return it }
        return raw
    }
}
