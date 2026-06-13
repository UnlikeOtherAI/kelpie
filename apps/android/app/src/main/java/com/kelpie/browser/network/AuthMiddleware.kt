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

    fun evaluate(req: ParsedRequest): AuthDecision {
        val ambiguous = rejectAmbiguousHeaders(req)
        if (ambiguous != null) return ambiguous

        if (req.path in UNAUTH_ALLOWLIST) {
            if (req.path == "/v1/pair" && req.method.equals("POST", ignoreCase = true)) {
                val csrf = csrfReject(req)
                if (csrf != null) return csrf
            }
            return AuthDecision.Unauthenticated
        }

        val bearer =
            extractBearer(req.headers)
                ?: return AuthDecision.Reject(401, "UNAUTHORIZED", "Authentication required")
        val clientId =
            store.validateBearer(bearer)
                ?: return AuthDecision.Reject(401, "UNAUTHORIZED", "Invalid bearer token")
        return AuthDecision.Authenticated(clientId)
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
        val contentType = req.headers["content-type"]?.firstOrNull()?.lowercase() ?: ""
        if (!contentType.startsWith("application/json")) {
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

    private fun extractBearer(headers: Map<String, List<String>>): String? {
        val value = headers["authorization"]?.firstOrNull() ?: return null
        if (!value.lowercase().startsWith("bearer ")) return null
        val token = value.drop("bearer ".length).trim()
        return token.ifEmpty { null }
    }
}
