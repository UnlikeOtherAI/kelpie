import WebKit

/// Cookie request handlers for `BrowserManagementHandler`.
///
/// Honors the documented `get-cookies`/`delete-cookies` `url` scope and the
/// `delete-cookies` `domain` filter, matching Android's `CookieManager`
/// semantics (see `CookieScope`). `get-cookies` with `all` or `partition` reads a
/// whole store instead of the current page's cookies.
extension BrowserManagementHandler {
    @MainActor
    func getCookies(_ body: [String: Any]) async -> [String: Any] {
        if let invalid = Self.invalidCookieField(body, strings: ["tabId", "partition", "domain", "name", "url"], flags: ["all"]) {
            return invalid
        }
        let wholeStore = body["all"] as? Bool == true || body["partition"] != nil
        let target: HandlerContext.CookieTarget
        var scopeURL = body["url"] as? String
        if wholeStore {
            switch resolveCookieTarget(body) {
            case .target(let resolved): target = resolved
            case .failure(let response): return response
            }
        } else {
            do {
                // Without `all`, the scope defaults to the current page (matches Android).
                let renderer = try context.resolveRenderer(tabId: HandlerContext.tabId(from: body))
                target = context.cookieTarget(for: renderer)
                scopeURL = scopeURL ?? renderer.currentURL?.absoluteString ?? "http://localhost/"
            } catch {
                return tabErrorResponse(from: error) ?? errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
            }
        }
        var cookies: [BrowserCookie]
        do {
            cookies = try await context.withCookies(target) { try await $0.all() }
        } catch {
            return Self.cookieStoreUnavailable()
        }
        if let name = body["name"] as? String { cookies = cookies.filter { $0.name == name } }
        if let domain = body["domain"] as? String { cookies = cookies.filter { CookieRequest.domain($0, matches: domain) } }
        if let scopeURL { cookies = CookieScope.scoped(cookies, toURL: scopeURL) }
        return successResponse(["cookies": cookies.map(CookieRequest.json), "count": cookies.count, "complete": true])
    }

    @MainActor
    func setCookie(_ body: [String: Any]) async -> [String: Any] {
        guard let name = body["name"] as? String,
              let value = body["value"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "name and value required")
        }
        do {
            let renderer = try context.resolveRenderer(tabId: HandlerContext.tabId(from: body))
            let defaultHost = renderer.currentURL?.host ?? "localhost"
            guard let parsed = CookieFactory.make(name: name, value: value, body: body, defaultHost: defaultHost) else {
                return errorResponse(code: "COOKIE_ERROR", message: "Failed to create cookie")
            }
            let cookie = BrowserCookie(parsed)
            let stored = try await context.withCookies(context.cookieTarget(for: renderer)) { await $0.set([cookie]) }
            guard stored.first == true else {
                return errorResponse(code: "COOKIE_ERROR", message: "The browser refused the cookie")
            }
            return successResponse()
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
    }

    @MainActor
    func deleteCookies(_ body: [String: Any]) async -> [String: Any] {
        let deleteAll = body["deleteAll"] as? Bool ?? false
        let nameFilter = body["name"] as? String
        let domainFilter = body["domain"] as? String
        let urlScope = body["url"] as? String
        do {
            let renderer = try context.resolveRenderer(tabId: HandlerContext.tabId(from: body))
            // No selector supplied: preserve prior behavior (no-op) rather than
            // wiping the store on an empty request.
            guard deleteAll || nameFilter != nil || domainFilter != nil else {
                return successResponse(["deleted": 0])
            }
            let deleted = try await context.withCookies(context.cookieTarget(for: renderer)) { jar -> Int in
                var candidates = try await jar.all()
                // Only when nothing narrows the scope is the whole store wiped.
                if deleteAll && nameFilter == nil && domainFilter == nil && urlScope == nil {
                    try await jar.deleteAll()
                    return candidates.count
                }
                if let urlScope { candidates = CookieScope.scoped(candidates, toURL: urlScope) }
                let doomed = candidates.filter { cookie in
                    (nameFilter == nil || cookie.name == nameFilter) &&
                        (domainFilter.map { CookieScope.domainMatches(cookie.domain, filter: $0) } ?? true)
                }
                return try await jar.delete(doomed.map(\.key))
            }
            return successResponse(["deleted": deleted])
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            if error is HandlerError { return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription) }
            return Self.cookieStoreUnavailable()
        }
    }

    static func cookieStoreUnavailable() -> [String: Any] {
        errorResponse(
            code: "COOKIE_STORE_UNAVAILABLE",
            message: "The cookie store could not be read completely. Nothing was reported or changed; retry."
        )
    }

    /// `INVALID_PARAMS` for the first field of the wrong type, else nil.
    static func invalidCookieField(_ body: [String: Any], strings: [String], flags: [String] = []) -> [String: Any]? {
        if let field = strings.first(where: { body[$0] != nil && !(body[$0] is String) }) {
            return errorResponse(code: "INVALID_PARAMS", message: "\(field) must be a string")
        }
        if let field = flags.first(where: { body[$0] != nil && !(body[$0] is Bool) }) {
            return errorResponse(code: "INVALID_PARAMS", message: "\(field) must be a boolean")
        }
        return nil
    }
}
