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
