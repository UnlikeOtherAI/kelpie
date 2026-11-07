import Foundation

/// Builds an `HTTPCookie` from a `set-cookie` request body.
///
/// `HTTPCookie(properties:)` exposes no key for `HttpOnly` (and is finicky with
/// `Secure`/`SameSite`/`Expires`), so an agent could never set an httpOnly
/// session cookie that way. Instead we assemble a standard `Set-Cookie` header
/// and let `HTTPCookie.cookies(withResponseHeaderFields:for:)` parse it — that
/// path preserves `isHTTPOnly`, `isSecure`, `sameSitePolicy`, and `expiresDate`,
/// matching how Android builds cookies via `CookieManager`.
enum CookieFactory {
    /// - Parameters:
    ///   - name: Cookie name (required).
    ///   - value: Cookie value (required).
    ///   - body: Request body; reads `path`, `domain`, `expires`, `secure`,
    ///     `httpOnly`, `sameSite`.
    ///   - defaultHost: Host used to scope the cookie when no `domain` is given.
    /// - Returns: The parsed cookie, or `nil` if the header could not be parsed.
    static func make(name: String, value: String, body: [String: Any], defaultHost: String) -> HTTPCookie? {
        let path = body["path"] as? String ?? "/"
        let domain = body["domain"] as? String

        var attributes = ["Path=\(path)"]
        if let domain { attributes.append("Domain=\(domain)") }
        if let expires = body["expires"] as? String { attributes.append("Expires=\(expires)") }
        if body["secure"] as? Bool == true { attributes.append("Secure") }
        if body["httpOnly"] as? Bool == true { attributes.append("HttpOnly") }
        if let sameSite = body["sameSite"] as? String { attributes.append("SameSite=\(sameSite)") }

        let header = (["\(name)=\(value)"] + attributes).joined(separator: "; ")

        // The URL host must domain-match the cookie for the parser to accept it.
        let host = domain.map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 } ?? defaultHost
        guard let url = URL(string: "https://\(host)/") else { return nil }

        return HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: url).first
    }
}

/// Scopes a set of `HTTPCookie`s to a request `url` / `domain`, mirroring how
/// Android's `CookieManager.getCookie(url)` and the `delete-cookies` domain
/// filter behave, so `get-cookies`/`delete-cookies` return parity across
/// platforms.
enum CookieScope {
    /// Returns only the cookies that would be sent to `urlString`: the URL host
    /// must domain-match the cookie, the URL path must be within the cookie
    /// path, and a `Secure` cookie requires an `https` URL. An unparseable URL
    /// yields an empty set (matching Android, which scopes to that URL's host).
    static func scoped(_ cookies: [HTTPCookie], toURL urlString: String) -> [HTTPCookie] {
        guard let url = URL(string: urlString), let host = url.host else { return [] }
        let path = url.path.isEmpty ? "/" : url.path
        let isSecureScheme = url.scheme?.lowercased() == "https"
        return cookies.filter { cookie in
            guard hostMatches(host, cookieDomain: cookie.domain) else { return false }
            guard pathMatches(path, cookiePath: cookie.path) else { return false }
            if cookie.isSecure && !isSecureScheme { return false }
            return true
        }
    }

    /// Exact domain filter for `delete-cookies`, tolerant of a leading dot on
    /// either side (WebKit may store `.example.com`; callers pass `example.com`).
    static func domainMatches(_ cookieDomain: String, filter: String) -> Bool {
        stripDot(cookieDomain) == stripDot(filter)
    }

    static func hostMatches(_ host: String, cookieDomain: String) -> Bool {
        let cleanHost = host.lowercased()
        let cleanDomain = stripDot(cookieDomain).lowercased()
        if cleanHost == cleanDomain { return true }
        // A dotted cookie domain matches the host and any subdomain of it.
        if cookieDomain.hasPrefix(".") {
            return cleanHost.hasSuffix("." + cleanDomain)
        }
        return false
    }

    static func pathMatches(_ requestPath: String, cookiePath: String) -> Bool {
        let cookiePath = cookiePath.isEmpty ? "/" : cookiePath
        if requestPath == cookiePath { return true }
        if requestPath.hasPrefix(cookiePath) {
            return cookiePath.hasSuffix("/") || requestPath.dropFirst(cookiePath.count).hasPrefix("/")
        }
        return false
    }

    private static func stripDot(_ value: String) -> String {
        value.hasPrefix(".") ? String(value.dropFirst()) : value
    }
}
