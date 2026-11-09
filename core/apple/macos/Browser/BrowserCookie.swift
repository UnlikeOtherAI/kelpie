import Foundation

/// One cookie as a browser engine holds it, independent of WebKit and Chromium types.
///
/// `domain` keeps the engine's spelling: a leading dot marks a domain cookie and a bare
/// host is host-only. `sameSite` uses the four wire names; `nil` means the engine reported
/// a value it cannot name, and such a cookie is never written anywhere.
struct BrowserCookie: Equatable {
    enum SameSite: String, CaseIterable {
        case strict = "Strict"
        case lax = "Lax"
        /// `SameSite=None`; not `.none`, which would read as a missing value.
        case noRestriction = "None"
        case unspecified = "Unspecified"
    }

    /// Cookie identity: domain without case, path and name.
    struct Key: Hashable {
        let domain: String
        let path: String
        let name: String
    }

    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Date?
    var secure: Bool
    var httpOnly: Bool
    var sameSite: SameSite?
    /// A partitioned (CHIPS) cookie. It cannot be recreated unpartitioned, so it is never
    /// copied or synced.
    var partitioned = false

    var key: Key { Key(domain: domain.lowercased(), path: path, name: name) }

    /// The domain without its leading dot, the form the read-back contract compares.
    var bareDomain: String { Self.bare(domain) }

    static func bare(_ domain: String) -> String {
        (domain.hasPrefix(".") ? String(domain.dropFirst()) : domain).lowercased()
    }
}

// MARK: - WebKit

extension BrowserCookie {
    init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path.isEmpty ? "/" : cookie.path
        expires = cookie.expiresDate
        secure = cookie.isSecure
        httpOnly = cookie.isHTTPOnly
        // WebKit reports an absent attribute as nil and, where it can tell, None as "none".
        switch cookie.sameSitePolicy?.rawValue.lowercased() {
        case nil: sameSite = .unspecified
        case "lax": sameSite = .lax
        case "strict": sameSite = .strict
        case "none": sameSite = .noRestriction
        default: sameSite = nil
        }
        partitioned = Self.isPartitioned(cookie)
    }

    /// Foundation names a cookie's partition in a property whose key contains "partition".
    private static func isPartitioned(_ cookie: HTTPCookie) -> Bool {
        (cookie.properties ?? [:]).contains { key, value in
            guard key.rawValue.lowercased().contains("partition") else { return false }
            switch value {
            case is NSNull: return false
            case let text as String: return !text.isEmpty
            case let number as NSNumber: return number.boolValue
            default: return true
            }
        }
    }

    /// The `HTTPCookie` WebKit stores, or nil when Foundation rejects the attributes.
    var httpCookie: HTTPCookie? {
        guard let sameSite, !partitioned else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path.isEmpty ? "/" : path
        ]
        if let expires { properties[.expires] = expires }
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        switch sameSite {
        case .unspecified: break
        case .lax: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax.rawValue
        case .strict: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict.rawValue
        case .noRestriction: properties[.sameSitePolicy] = "none"
        }
        return HTTPCookie(properties: properties)
    }
}

// MARK: - Chromium bridge dictionaries

extension BrowserCookie {
    /// Reads a `CEFBridge (Cookies)` dictionary; nil when a required field is missing.
    init?(bridge dict: [String: Any]) {
        guard let name = dict["name"] as? String, let value = dict["value"] as? String,
              let domain = dict["domain"] as? String, let path = dict["path"] as? String else { return nil }
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path.isEmpty ? "/" : path
        expires = (dict["expires"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        secure = dict["secure"] as? Bool ?? false
        httpOnly = dict["httpOnly"] as? Bool ?? false
        sameSite = (dict["sameSite"] as? String).flatMap(SameSite.init(rawValue:))
    }

    /// The dictionary `CEFBridge.setGlobalCookie` takes, or nil for an unnamed SameSite.
    ///
    /// Chromium refuses `SameSite=None` without `Secure`, while WebKit reads a cookie stored
    /// without the attribute back as `None`. Such a cookie is written as `Unspecified`, the
    /// one value Chromium accepts for it; the read-back shows the change.
    var bridgeDictionary: [String: Any]? {
        guard var sameSite, !partitioned else { return nil }
        if sameSite == .noRestriction && !secure { sameSite = .unspecified }
        var dict: [String: Any] = [
            "name": name, "value": value, "domain": domain, "path": path,
            "secure": secure, "httpOnly": httpOnly, "sameSite": sameSite.rawValue
        ]
        if let expires { dict["expires"] = expires.timeIntervalSince1970 }
        return dict
    }
}

// MARK: - Sync wire shape

extension BrowserCookie {
    /// The core-sync engine-cookie shape, or nil when the cookie cannot be described.
    var syncWireJSON: [String: Any]? {
        guard let sameSite, !partitioned else { return nil }
        return [
            "domain": domain, "path": path, "name": name, "value": value,
            "expires": expires.map { Int64(floor($0.timeIntervalSince1970)) as Any } ?? NSNull(),
            "secure": secure, "httpOnly": httpOnly, "sameSite": sameSite.rawValue
        ]
    }

    /// Reads a core-sync cookie: `expires` is whole Unix seconds or null.
    init?(syncWire dict: [String: Any]) {
        guard let name = dict["name"] as? String, let domain = dict["domain"] as? String else { return nil }
        self.name = name
        self.domain = domain
        value = dict["value"] as? String ?? ""
        let path = dict["path"] as? String ?? "/"
        self.path = path.isEmpty ? "/" : path
        expires = (dict["expires"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        secure = dict["secure"] as? Bool ?? false
        httpOnly = dict["httpOnly"] as? Bool ?? false
        sameSite = (dict["sameSite"] as? String).flatMap(SameSite.init(rawValue:)) ?? .unspecified
    }
}
