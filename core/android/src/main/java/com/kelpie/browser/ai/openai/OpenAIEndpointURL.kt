package com.kelpie.browser.ai.openai

/**
 * A normalised OpenAI-compatible base URL (`scheme://host[:port]/path`, no trailing slash).
 * See "URL handling" in docs/api/ai-endpoints.md.
 */
data class OpenAIEndpointURL(
    val scheme: String,
    /** Lower-cased host; IPv6 literals are stored without brackets. */
    val host: String,
    val port: Int?,
    val path: String,
) {
    val isIPv6: Boolean get() = host.contains(':')

    private val hostForURL: String get() = if (isIPv6) "[$host]" else host

    val baseURL: String get() = "$scheme://$hostForURL${port?.let { ":$it" } ?: ""}$path"

    val isLoopback: Boolean get() = isLoopbackHost(host)

    override fun toString(): String = baseURL

    /** Joins an operation (`models`, `chat/completions`) without ever producing `//` or `/v1/v1`. */
    fun join(operation: String): String = "$baseURL/${operation.trimStart('/')}"

    companion object {
        const val DEFAULT_PATH = "/v1"
        private val SCHEMES = setOf("http", "https")
        private val OPERATIONS = listOf("/chat/completions", "/completions", "/models", "/embeddings")
        private val HOST_CHARS = Regex("^[a-z0-9._-]+$")
        private val IPV6_CHARS = Regex("^[0-9a-f:.]+(%[a-z0-9._~-]+)?$")

        /** Normalises user input or throws [OpenAIException] with `INVALID_ENDPOINT_URL`. */
        fun normalize(input: String): OpenAIEndpointURL {
            val trimmed = input.trim()
            if (trimmed.isEmpty()) invalid("Enter an http:// or https:// URL")
            if (trimmed.any { it.isWhitespace() }) invalid("The URL must not contain spaces")
            val separator = trimmed.indexOf("://")
            if (separator <= 0) invalid("The URL must start with http:// or https://")
            val scheme = trimmed.substring(0, separator).lowercase()
            if (scheme !in SCHEMES) invalid("Only http:// and https:// URLs are supported")

            val rest = trimmed.substring(separator + 3)
            if (rest.contains('?')) invalid("Remove the query string from the URL")
            if (rest.contains('#')) invalid("Remove the fragment from the URL")
            val slash = rest.indexOf('/')
            val authority = if (slash >= 0) rest.substring(0, slash) else rest
            val rawPath = if (slash >= 0) rest.substring(slash) else ""
            if (authority.contains('@')) invalid("Do not put credentials in the URL; use the API key field")
            if (authority.isEmpty()) invalid("The URL needs a host")

            val (host, port) = parseAuthority(authority)
            return OpenAIEndpointURL(scheme, host, port, normalizePath(rawPath))
        }

        /** Returns null instead of throwing. */
        fun normalizeOrNull(input: String): OpenAIEndpointURL? =
            try {
                normalize(input)
            } catch (_: OpenAIException) {
                null
            }

        fun isLoopbackHost(rawHost: String): Boolean {
            val host = rawHost.lowercase().removePrefix("[").removeSuffix("]")
            if (host == "localhost" || host.endsWith(".localhost")) return true
            if (host == "::1" || host == "0:0:0:0:0:0:0:1") return true
            val octets = host.split('.')
            return octets.size == 4 && octets[0] == "127" && octets.all { it.toIntOrNull() in 0..255 }
        }

        private fun parseAuthority(authority: String): Pair<String, Int?> {
            if (authority.startsWith("[")) {
                val close = authority.indexOf(']')
                if (close < 0) invalid("The IPv6 address is missing its closing ]")
                val host = authority.substring(1, close).lowercase()
                if (host.isEmpty() || !host.contains(':') || !IPV6_CHARS.matches(host)) invalid("The IPv6 address is not valid")
                val after = authority.substring(close + 1)
                if (after.isEmpty()) return host to null
                if (!after.startsWith(":")) invalid("Unexpected characters after the IPv6 address")
                return host to parsePort(after.substring(1))
            }
            val colonCount = authority.count { it == ':' }
            if (colonCount > 1) invalid("IPv6 addresses must be written in brackets, e.g. http://[::1]:8080")
            val host = authority.substringBefore(':').lowercase()
            if (host.isEmpty()) invalid("The URL needs a host")
            if (!HOST_CHARS.matches(host) || host.startsWith('.') || host.contains("..")) invalid("The host name is not valid")
            val port = if (colonCount == 1) parsePort(authority.substringAfter(':')) else null
            return host to port
        }

        private fun parsePort(text: String): Int {
            if (text.isEmpty() || !text.all { it.isDigit() } || text.length > 5) invalid("The port must be a number from 1 to 65535")
            val port = text.toInt()
            if (port !in 1..65535) invalid("The port must be a number from 1 to 65535")
            return port
        }

        private fun normalizePath(rawPath: String): String {
            var path = rawPath.replace(Regex("/{2,}"), "/").trimEnd('/')
            val operation = OPERATIONS.firstOrNull { path.endsWith(it, ignoreCase = true) }
            if (operation != null) {
                path = path.substring(0, path.length - operation.length).trimEnd('/')
            }
            return path.ifEmpty { DEFAULT_PATH }
        }

        private fun invalid(message: String): Nothing = throw OpenAIException(OpenAIErrorCode.INVALID_ENDPOINT_URL, message)
    }
}
