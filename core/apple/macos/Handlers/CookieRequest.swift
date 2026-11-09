import Foundation

/// Agent-facing cookie JSON for `get-cookies`, `set-cookies` and `copy-cookies`.
enum CookieRequest {
    static let maxImportCount = 500

    /// The `get-cookies` shape. `expires` keeps its existing text form; `sameSite` uses
    /// the four wire names.
    static func json(_ cookie: BrowserCookie) -> [String: Any] {
        [
            "name": cookie.name, "value": cookie.value, "domain": cookie.domain, "path": cookie.path,
            "expires": cookie.expires?.description ?? NSNull(), "httpOnly": cookie.httpOnly,
            "secure": cookie.secure, "sameSite": cookie.sameSite?.rawValue ?? NSNull()
        ]
    }

    /// A `failed` entry: identity and reason, never the value.
    static func failure(index: Int?, name: Any?, domain: Any?, error: String) -> [String: Any] {
        var entry: [String: Any] = [
            "name": name as? String ?? NSNull(), "domain": domain as? String ?? NSNull(), "error": error
        ]
        if let index { entry["index"] = index }
        return entry
    }

    /// Parses one `set-cookies` entry, or returns the per-cookie error code.
    static func cookie(from item: Any) -> Result<BrowserCookie, CookieError> {
        guard let dict = item as? [String: Any] else { return .failure(.invalid) }
        guard let name = dict["name"] as? String, !name.isEmpty,
              let value = dict["value"] as? String,
              let domain = dict["domain"] as? String, BrowserCookie.bare(domain).isEmpty == false else {
            return .failure(.invalid)
        }
        let path = dict["path"] == nil || dict["path"] is NSNull ? "/" : dict["path"] as? String
        guard let path, path.hasPrefix("/") else { return .failure(.invalid) }
        guard let secure = flag(dict["secure"]), let httpOnly = flag(dict["httpOnly"]) else { return .failure(.invalid) }
        guard let sameSite = parseSameSite(dict["sameSite"]) else { return .failure(.invalid) }
        guard let expiry = parseExpiry(dict["expires"]) else { return .failure(.invalid) }
        return .success(BrowserCookie(
            name: name,
            value: value,
            domain: domain.lowercased(),
            path: path,
            expires: expiry.date,
            secure: secure,
            httpOnly: httpOnly,
            sameSite: sameSite
        ))
    }

    enum CookieError: String, Error {
        case invalid = "INVALID_COOKIE"
        case refused = "REFUSED"
        case partitioned = "PARTITIONED"
    }

    /// True when the cookie's host equals `filter` or is a subdomain of it.
    static func domain(_ cookie: BrowserCookie, matches filter: String) -> Bool {
        let wanted = BrowserCookie.bare(filter)
        let host = cookie.bareDomain
        return host == wanted || host.hasSuffix("." + wanted)
    }

    private static func flag(_ value: Any?) -> Bool? {
        guard let value, !(value is NSNull) else { return false }
        return value as? Bool
    }

    /// `Strict`, `Lax`, `None` or `Unspecified`, ignoring case. Missing or empty is
    /// `Unspecified`, the absent attribute.
    private static func parseSameSite(_ value: Any?) -> BrowserCookie.SameSite? {
        guard let value, !(value is NSNull) else { return .unspecified }
        guard let text = value as? String else { return nil }
        if text.isEmpty { return .unspecified }
        return BrowserCookie.SameSite.allCases.first { $0.rawValue.caseInsensitiveCompare(text) == .orderedSame }
    }

    private enum Expiry {
        case session
        case at(Date)

        var date: Date? {
            if case .at(let date) = self { return date }
            return nil
        }
    }

    /// Unix seconds, ISO 8601, the `get-cookies` text form, or null for a session cookie;
    /// nil when the value cannot be read.
    private static func parseExpiry(_ value: Any?) -> Expiry? {
        guard let value, !(value is NSNull) else { return .session }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return .at(Date(timeIntervalSince1970: number.doubleValue))
        }
        guard let text = value as? String else { return nil }
        return dateParsers.lazy.compactMap { $0(text) }.first.map(Expiry.at)
    }

    private static let dateParsers: [(String) -> Date?] = {
        let iso = ISO8601DateFormatter()
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let described = DateFormatter()
        described.locale = Locale(identifier: "en_US_POSIX")
        described.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let http = DateFormatter()
        http.locale = Locale(identifier: "en_US_POSIX")
        http.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return [iso.date(from:), isoFractional.date(from:), described.date(from:), http.date(from:)]
    }()
}
