package com.kelpie.browser.network

/**
 * Parsed view of an HTTP request — enough for the auth middleware to apply
 * deny-by-default + CSRF policy before the request reaches the router.
 */
data class ParsedRequest(
    val method: String,
    /** Decoded request-target path (no query string). */
    val path: String,
    /** Header name (lower-cased) -> all values seen (preserves duplicates). */
    val headers: Map<String, List<String>>,
    /** True if any `Transfer-Encoding` header was seen. */
    val hasTransferEncoding: Boolean,
    /** Authoritative socket peer address as a printable string. */
    val sourceAddress: String,
)

sealed interface AuthDecision {
    data object Unauthenticated : AuthDecision

    data class Authenticated(
        val clientId: String,
        val computerAddress: String? = null,
    ) : AuthDecision

    data class Reject(
        val status: Int,
        val errorCode: String,
        val message: String,
    ) : AuthDecision
}

/**
 * Enforces the pairing/auth state machine.
 *
 * Exact-match decoded-path allowlist — everything else requires a bearer.
 */
class AuthMiddleware(
    private val store: PairingStore,
) {
    companion object {
        val UNAUTH_ALLOWLIST: Set<String> =
            setOf(
                "/v1/pair",
                "/v1/pair/status",
                "/v1/get-device-info",
                // Health intentionally unauthenticated — useful for operator probes
                // and contains no sensitive data.
                "/health",
            )
    }

    fun evaluate(
        req: ParsedRequest,
        verifiedAccountClientId: String? = null,
    ): AuthDecision {
        val ambiguous = rejectAmbiguousHeaders(req)
        if (ambiguous != null) return ambiguous

        if (req.path in UNAUTH_ALLOWLIST && (req.path != "/v1/pair" || req.method.equals("POST", ignoreCase = true))) {
            if (req.path == "/v1/pair" && req.method.equals("POST", ignoreCase = true)) {
                val csrf = csrfReject(req)
                if (csrf != null) return csrf
            }
            return AuthDecision.Unauthenticated
        }

        val trustedClient = store.trustedComputers.clientId(req.sourceAddress)
        val computerRejection = if (trustedClient != null) trustedRequestReject(req) else null
        val computerClient = trustedClient.takeIf { computerRejection == null }
        val clientId =
            computerClient ?: run {
                val bearer = extractBearer(req.headers) ?: return computerRejection ?: AuthDecision.Reject(401, "UNAUTHORIZED", "Authentication required")
                store.validateBearer(bearer) ?: verifiedAccountClientId
                    ?: return AuthDecision.Reject(401, "UNAUTHORIZED", "Invalid bearer token")
            }
        if (req.path == "/mcp" || req.path == "/v1/mcp") {
            if (req.headers.containsKey("origin")) return AuthDecision.Reject(403, "FORBIDDEN", "Browser Origin is not permitted on MCP")
            val versions = req.headers["mcp-protocol-version"]
            if (versions != null && (versions.size != 1 || versions.single() !in setOf("2025-03-26", "2025-06-18"))) {
                return AuthDecision.Reject(400, "BAD_REQUEST", "Unsupported MCP protocol version")
            }
        }
        return AuthDecision.Authenticated(clientId, if (computerClient != null) store.trustedComputers.canonicalAddress(req.sourceAddress) else null)
    }

    private fun rejectAmbiguousHeaders(req: ParsedRequest): AuthDecision.Reject? {
        if (req.hasTransferEncoding) {
            return AuthDecision.Reject(400, "BAD_REQUEST", "Transfer-Encoding not accepted")
        }
        if ((req.headers["authorization"]?.size ?: 0) > 1) {
            return AuthDecision.Reject(400, "BAD_REQUEST", "Duplicate Authorization header")
        }
        if ((req.headers["content-length"]?.size ?: 0) > 1) {
            return AuthDecision.Reject(400, "BAD_REQUEST", "Duplicate Content-Length header")
        }
        return null
    }

    private fun csrfReject(req: ParsedRequest): AuthDecision.Reject? {
        val site = req.headers["sec-fetch-site"]
        if (site != null && site != listOf("none") && site != listOf("same-origin")) {
            return AuthDecision.Reject(403, "FORBIDDEN", "Cross-site pairing is not permitted")
        }
        val contentType =
            req.headers["content-type"]
                ?.firstOrNull()
                ?.substringBefore(';')
                ?.trim()
                ?.lowercase() ?: ""
        if (contentType != "application/json") {
            return AuthDecision.Reject(415, "UNSUPPORTED_MEDIA_TYPE", "Content-Type must be application/json")
        }
        val origin = req.headers["origin"]?.firstOrNull()
        if (origin != null) {
            // Any browser-supplied Origin (including `null` from sandboxed iframes)
            // is rejected. CLI fetch in Node does not set Origin.
            return AuthDecision.Reject(403, "FORBIDDEN", "Origin '$origin' not permitted on pair endpoint")
        }
        return null
    }

    private fun trustedRequestReject(req: ParsedRequest): AuthDecision.Reject? {
        val site = req.headers["sec-fetch-site"]
        if (req.headers.containsKey("origin") || (site != null && site != listOf("none") && site != listOf("same-origin"))) {
            return AuthDecision.Reject(403, "FORBIDDEN", "Browser requests cannot use computer approval")
        }
        val hosts = req.headers["host"]
        if (hosts == null || hosts.size != 1 || !store.trustedComputers.safeHost(hosts.single())) {
            return AuthDecision.Reject(403, "FORBIDDEN", "A local Host header is required")
        }
        if (req.method == "POST" &&
            req.headers["content-type"]
                ?.firstOrNull()
                ?.substringBefore(';')
                ?.trim()
                ?.lowercase() != "application/json"
        ) {
            return AuthDecision.Reject(415, "UNSUPPORTED_MEDIA_TYPE", "Content-Type must be application/json")
        }
        return null
    }

    private fun extractBearer(headers: Map<String, List<String>>): String? {
        val value = headers["authorization"]?.firstOrNull() ?: return null
        if (!value.lowercase().startsWith("bearer ")) return null
        val token = value.drop("bearer ".length).trim()
        return token.ifEmpty { null }
    }
}
