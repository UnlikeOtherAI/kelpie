import WebKit

/// Cookie request handlers for `BrowserManagementHandler`.
///
/// Honors the documented `get-cookies`/`delete-cookies` `url` scope and the
/// `delete-cookies` `domain` filter, matching Android's `CookieManager`
/// semantics (see `CookieScope`).
extension BrowserManagementHandler {
    @MainActor
    func getCookies(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        do {
            let renderer = try context.resolveRenderer(tabId: tabId)
            let cookies: [HTTPCookie]
            if tabId == nil {
                cookies = await context.allCookies()
            } else {
                cookies = await renderer.allCookies()
            }
            let name = body["name"] as? String
            var filtered = name != nil ? cookies.filter { $0.name == name } : cookies
            if let url = body["url"] as? String {
                filtered = CookieScope.scoped(filtered, toURL: url)
            }
            let cookieList = filtered.map { cookie -> [String: Any] in
                ["name": cookie.name, "value": cookie.value, "domain": cookie.domain, "path": cookie.path,
                 "expires": cookie.expiresDate?.description ?? NSNull(), "httpOnly": cookie.isHTTPOnly,
                 "secure": cookie.isSecure, "sameSite": cookie.sameSitePolicy?.rawValue ?? ""]
            }
            return successResponse(["cookies": cookieList, "count": cookieList.count])
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
    }

    @MainActor
    func setCookie(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        guard let name = body["name"] as? String,
              let value = body["value"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "name and value required")
        }
        do {
            let renderer = try context.resolveRenderer(tabId: tabId)
            let defaultHost = renderer.currentURL?.host ?? "localhost"
            guard let cookie = CookieFactory.make(name: name, value: value, body: body, defaultHost: defaultHost) else {
                return errorResponse(code: "COOKIE_ERROR", message: "Failed to create cookie")
            }
            if tabId == nil {
                await context.setCookie(cookie)
            } else {
                await renderer.setCookies([cookie])
            }
            return successResponse()
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
    }

    @MainActor
    func deleteCookies(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        do {
            let renderer = try context.resolveRenderer(tabId: tabId)
            var candidates = await renderer.allCookies()
            let urlScope = body["url"] as? String
            if let urlScope {
                candidates = CookieScope.scoped(candidates, toURL: urlScope)
            }
            let deleteAll = body["deleteAll"] as? Bool ?? false
            let nameFilter = body["name"] as? String
            let domainFilter = body["domain"] as? String

            // No selector supplied: preserve prior behavior (no-op) rather than
            // wiping the store on an empty request.
            guard deleteAll || nameFilter != nil || domainFilter != nil else {
                return successResponse(["deleted": 0])
            }

            // Fast path: only when nothing narrows the scope can we wipe the
            // whole store, which also clears the cross-renderer shared jar.
            if deleteAll && nameFilter == nil && domainFilter == nil && urlScope == nil {
                let deleted = candidates.count
                if tabId == nil {
                    await context.deleteAllCookies()
                } else {
                    await renderer.deleteAllCookies()
                }
                return successResponse(["deleted": deleted])
            }

            var deleted = 0
            for cookie in candidates {
                let matchesName = nameFilter == nil || cookie.name == nameFilter
                let matchesDomain = domainFilter.map { CookieScope.domainMatches(cookie.domain, filter: $0) } ?? true
                guard matchesName && matchesDomain else { continue }
                if tabId == nil {
                    await context.deleteCookie(cookie)
                } else {
                    await renderer.deleteCookie(cookie)
                }
                deleted += 1
            }
            return successResponse(["deleted": deleted])
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
    }
}
