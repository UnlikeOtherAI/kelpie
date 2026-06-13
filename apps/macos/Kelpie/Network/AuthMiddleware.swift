import Foundation

/// Parsed HTTP request enough to apply auth + CSRF policy. The HTTPServer
/// builds one of these per request before routing.
struct ParsedHTTPRequest {
    let method: String
    /// Decoded request-target path (no query string).
    let path: String
    /// Raw query string (post-`?`, may be empty).
    let query: String
    /// Header name -> all values (preserves duplicates for ambiguity detection).
    let headers: [String: [String]]
    let body: Data
    /// Authoritative socket peer address as a printable string ("192.168.1.42" or "[fe80::1]").
    let sourceAddress: String
    /// True when any `Transfer-Encoding` header was seen.
    let hasTransferEncoding: Bool
}

/// Result of running the auth middleware over a request.
enum AuthDecision: Equatable {
    /// Request is allowed without a bearer — endpoint is on the unauth allowlist.
    case unauthenticated
    /// Request is bearer-authenticated; `clientId` is the resolved owner.
    case authenticated(clientId: String)
    /// Request must be rejected with the given status + JSON body keys.
    case reject(status: Int, errorCode: String, message: String)
}

/// Enforces the pairing/auth state machine on every request.
struct AuthMiddleware {
    /// Exact-match decoded-path allowlist. Pre-routing — every other path must
    /// supply a valid bearer token.
    static let unauthAllowlist: Set<String> = [
        "/v1/pair",
        "/v1/pair/status",
        "/v1/get-device-info",
        // Health is intentionally unauthenticated so operators can probe the
        // device without holding a token. It contains no sensitive data.
        "/health"
    ]

    let store: PairingStore

    func evaluate(_ req: ParsedHTTPRequest) -> AuthDecision {
        if let headerReject = rejectAmbiguousHeaders(req) {
            return headerReject
        }
        if Self.unauthAllowlist.contains(req.path) {
            if req.path == "/v1/pair", req.method == "POST" {
                if let csrf = csrfReject(req) { return csrf }
            }
            return .unauthenticated
        }
        // Everything else requires bearer.
        guard let bearer = extractBearer(req.headers) else {
            return .reject(status: 401, errorCode: "UNAUTHORIZED", message: "Authentication required")
        }
        guard let clientId = store.validateBearer(bearer) else {
            return .reject(status: 401, errorCode: "UNAUTHORIZED", message: "Invalid bearer token")
        }
        return .authenticated(clientId: clientId)
    }

    /// Reject requests that smuggle dangerous header combinations before they
    /// reach routing. Duplicate `Authorization`/`Content-Length` and any
    /// `Transfer-Encoding` are all hard rejects per the design.
    private func rejectAmbiguousHeaders(_ req: ParsedHTTPRequest) -> AuthDecision? {
        if req.hasTransferEncoding {
            return .reject(status: 400, errorCode: "BAD_REQUEST", message: "Transfer-Encoding not accepted")
        }
        if (req.headers["authorization"]?.count ?? 0) > 1 {
            return .reject(status: 400, errorCode: "BAD_REQUEST", message: "Duplicate Authorization header")
        }
        if (req.headers["content-length"]?.count ?? 0) > 1 {
            return .reject(status: 400, errorCode: "BAD_REQUEST", message: "Duplicate Content-Length header")
        }
        return nil
    }

    /// CSRF gate for `POST /v1/pair`. CLI fetch sends `Content-Type:
    /// application/json` and no `Origin`. Browser fetches always send `Origin`
    /// (or `Origin: null` from sandboxed iframes); reject both.
    private func csrfReject(_ req: ParsedHTTPRequest) -> AuthDecision? {
        let contentType = req.headers["content-type"]?.first?.lowercased() ?? ""
        if !contentType.hasPrefix("application/json") {
            return .reject(status: 415, errorCode: "UNSUPPORTED_MEDIA_TYPE", message: "Content-Type must be application/json")
        }
        if let origin = req.headers["origin"]?.first {
            // Any browser-supplied Origin (including `null` from sandboxed iframes)
            // is rejected. CLI fetch in Node does not set Origin.
            return .reject(status: 403, errorCode: "FORBIDDEN", message: "Origin '\(origin)' not permitted on pair endpoint")
        }
        return nil
    }

    private func extractBearer(_ headers: [String: [String]]) -> String? {
        guard let value = headers["authorization"]?.first else { return nil }
        let lower = value.lowercased()
        guard lower.hasPrefix("bearer ") else { return nil }
        let token = String(value.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }
}
