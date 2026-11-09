import Foundation

/// Converts between `HTTPCookie` and core-sync's wire shape:
/// `{domain, path, name, value, expires, secure, httpOnly, sameSite}` with `expires` in
/// whole Unix seconds or null and `sameSite` one of `Strict|Lax|None|Unspecified`.
///
/// A nil policy (no attribute) is `Unspecified`; Foundation and WebKit keep `none`
/// distinct. Any other policy string cannot be described and the cookie is skipped.
/// Apple's public cookie API does not expose partitioned (CHIPS) cookies; a cookie whose
/// properties carry a partition is skipped as well.
public enum SyncCookieWire {
    private static let httpOnlyKey = HTTPCookiePropertyKey("HttpOnly")

    /// The wire cookie, or nil when the cookie cannot be described or is partitioned.
    public static func json(from cookie: HTTPCookie) -> [String: Any]? {
        // Foundation reports "no port list" as an empty array; a real port list cannot be described.
        guard cookie.portList?.isEmpty ?? true, !isPartitioned(cookie), let sameSite = wireSameSite(cookie.sameSitePolicy) else {
            return nil
        }
        let domain = cookie.domain.lowercased()
        guard !domain.isEmpty, !cookie.name.isEmpty else { return nil }
        var expires: Any = NSNull()
        if !cookie.isSessionOnly {
            guard let date = cookie.expiresDate else { return nil }
            expires = NSNumber(value: Int64(date.timeIntervalSince1970.rounded(.down)))
        }
        return [
            "domain": domain,
            "path": cookie.path.isEmpty ? "/" : cookie.path,
            "name": cookie.name,
            "value": cookie.value,
            "expires": expires,
            "secure": cookie.isSecure,
            "httpOnly": cookie.isHTTPOnly,
            "sameSite": sameSite
        ]
    }

    /// An engine cookie for a wire cookie, or nil when a field is missing or invalid.
    /// A domain with a leading dot is a domain cookie; without one it is host-only.
    public static func httpCookie(from json: [String: Any]) -> HTTPCookie? {
        guard let domain = json["domain"] as? String, !domain.isEmpty, domain != ".",
              let name = json["name"] as? String, !name.isEmpty,
              let value = json["value"] as? String,
              let secure = SyncJSON.flag(json["secure"]), let httpOnly = SyncJSON.flag(json["httpOnly"]) else { return nil }
        let path = (json["path"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "/"
        guard path.hasPrefix("/") else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [.domain: domain.lowercased(), .path: path, .name: name, .value: value]
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[httpOnlyKey] = "TRUE" }
        switch json["expires"] {
        case nil, is NSNull: break
        case let raw:
            guard let seconds = SyncJSON.int64(raw) else { return nil }
            properties[.expires] = Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        switch json["sameSite"] {
        case nil, is NSNull: break
        case let raw:
            guard let text = raw as? String, let policy = enginePolicy(text) else { return nil }
            if let policy { properties[.sameSitePolicy] = policy }
        }
        return HTTPCookie(properties: properties)
    }

    static func encode(_ cookies: [[String: Any]]) -> String { SyncJSON.string(cookies) }

    /// The domain without its leading dot, as the read-back contract compares it.
    static func host(of domain: String) -> String {
        let lowered = domain.lowercased()
        return lowered.hasPrefix(".") ? String(lowered.dropFirst()) : lowered
    }

    private static func wireSameSite(_ policy: HTTPCookieStringPolicy?) -> String? {
        guard let policy else { return "Unspecified" }
        switch policy.rawValue.lowercased() {
        case "lax": return "Lax"
        case "strict": return "Strict"
        case "none": return "None"
        default: return nil
        }
    }

    /// `.some(nil)` means "no attribute"; `nil` means the value is invalid.
    private static func enginePolicy(_ text: String) -> HTTPCookieStringPolicy?? {
        switch text.lowercased() {
        case "unspecified": return .some(nil)
        case "lax": return .some(.sameSiteLax)
        case "strict": return .some(.sameSiteStrict)
        case "none": return .some(HTTPCookieStringPolicy(rawValue: "none"))
        default: return nil
        }
    }

    private static func isPartitioned(_ cookie: HTTPCookie) -> Bool {
        guard let properties = cookie.properties else { return false }
        return properties.contains { key, value in
            guard key.rawValue.lowercased().contains("partition") else { return false }
            switch value {
            case is NSNull: return false
            case let text as String: return !text.isEmpty
            case let number as NSNumber: return number.boolValue
            default: return true
            }
        }
    }
}
