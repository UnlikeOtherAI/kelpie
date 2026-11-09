import WebKit

/// Cookie endpoints. A target is a tab (`tabId`), a named partition (`partition`) or,
/// with neither, the default website store. `expires` is ISO 8601 UTC or null (set-cookies
/// also accepts whole Unix seconds); `sameSite` is one of `Strict|Lax|None|Unspecified`.
/// `copy-cookies` moves cookies between stores without returning their values.
struct MobileCookieHandler {
    static let maxCookiesPerWrite = 500

    let context: HandlerContext

    func register(on router: Router) {
        router.register("get-cookies") { body in await getCookies(body) }
        router.register("set-cookie") { body in await setCookie(body) }
        router.register("set-cookies") { body in await setCookies(body) }
        router.register("copy-cookies") { body in await copyCookies(body) }
        router.register("delete-cookies") { body in await deleteCookies(body) }
        router.register("get-cookie-sync-status") { _ in successResponse(await MobileCookieSync.shared.status()) }
    }

    // MARK: - Targets

    private struct Target {
        let store: WKWebsiteDataStore
        /// The page whose cookies `get-cookies` returns when neither `url` nor `all` is given.
        let page: String?
    }

    private struct Refusal: Error {
        let response: [String: Any]

        init(_ code: String, _ message: String) { response = errorResponse(code: code, message: message) }
        init(_ response: [String: Any]) { self.response = response }
    }

    /// `currentPage`: with no explicit target, use the visible tab like `get-cookies`
    /// always has. Otherwise no target means the default store.
    @MainActor
    private func target(_ body: [String: Any], createPartition: Bool, currentPage: Bool = false) throws -> Target {
        if let raw = body["tabId"], !(raw is String) { throw Refusal("INVALID_PARAMS", "tabId must be a string") }
        if let raw = body["partition"], !(raw is String) { throw Refusal("INVALID_PARTITION", "partition must be a string") }
        let tabId = body["tabId"] as? String
        let partition = body["partition"] as? String
        if tabId != nil, partition != nil { throw Refusal("INVALID_PARAMS", "Use tabId or partition, not both") }
        if let tabId {
            guard let tab = context.tabStore?.tabs.first(where: { $0.id.uuidString == tabId }) else {
                throw Refusal("TAB_NOT_FOUND", "No tab with id \(tabId)")
            }
            return Target(store: tab.webView.configuration.websiteDataStore, page: tab.webView.url?.absoluteString ?? "http://localhost/")
        }
        if let partition {
            do {
                let registry = MobilePartitionRegistry.shared
                return Target(store: createPartition ? try registry.resolve(partition) : try registry.existing(partition), page: nil)
            } catch let failure as MobilePartitionRegistry.Failure {
                throw Refusal(failure.response)
            }
        }
        if currentPage {
            guard let webView = context.webView else { throw Refusal("NO_WEBVIEW", "No WebView") }
            return Target(store: webView.configuration.websiteDataStore, page: webView.url?.absoluteString ?? "http://localhost/")
        }
        return Target(store: KelpieWebsiteData.store, page: nil)
    }

    private static func sameStore(_ lhs: WKWebsiteDataStore, _ rhs: WKWebsiteDataStore) -> Bool {
        if lhs === rhs { return true }
        if #available(iOS 17.0, *), let left = lhs.identifier, let right = rhs.identifier { return left == right }
        return false
    }

    /// The cookie's host equals `domain` or is a subdomain of it; leading dots are ignored.
    static func inDomain(_ cookieDomain: String, _ domain: String) -> Bool {
        let host = SyncCookieWire.host(of: cookieDomain)
        let filter = SyncCookieWire.host(of: domain)
        return host == filter || host.hasSuffix("." + filter)
    }

    private static func stored(_ cookie: HTTPCookie, in cookies: [HTTPCookie]) -> Bool {
        cookies.contains {
            $0.name == cookie.name && $0.domain.lowercased() == cookie.domain.lowercased() && $0.path == cookie.path && $0.value == cookie.value
        }
    }

    private static func failure(_ index: Int, name: Any?, domain: Any?, _ code: String) -> [String: Any] {
        ["index": index, "name": name as? String ?? NSNull(), "domain": domain as? String ?? NSNull(), "error": code]
    }

    // MARK: - Read

    /// `all:true` returns every cookie in the target instead of the current page's.
    @MainActor
    private func getCookies(_ body: [String: Any]) async -> [String: Any] {
        guard let all = SyncJSON.flag(body["all"]) else { return errorResponse(code: "INVALID_PARAMS", message: "all must be a boolean") }
        if let raw = body["domain"], !(raw is String) { return errorResponse(code: "INVALID_PARAMS", message: "domain must be a string") }
        do {
            let target = try target(body, createPartition: false, currentPage: !all)
            var cookies = await target.store.httpCookieStore.allCookies()
            if let name = body["name"] as? String { cookies = cookies.filter { $0.name == name } }
            if let domain = body["domain"] as? String { cookies = cookies.filter { Self.inDomain($0.domain, domain) } }
            if let scope = body["url"] as? String ?? (all ? nil : target.page) { cookies = CookieScope.scoped(cookies, toURL: scope) }
            let described = cookies.compactMap(SyncCookieWire.json(from:)).map(CookieAPIFormat.apiJSON(fromWire:))
            var result: [String: Any] = ["cookies": described, "count": described.count, "complete": described.count == cookies.count]
            if described.count != cookies.count { result["skipped"] = cookies.count - described.count }
            return successResponse(result)
        } catch let refusal as Refusal {
            return refusal.response
        } catch {
            return errorResponse(code: "COOKIE_ERROR", message: error.localizedDescription)
        }
    }

    // MARK: - Write

    /// Writes up to 500 wire cookies; each is read back and reported if the engine did not keep it.
    @MainActor
    private func setCookies(_ body: [String: Any]) async -> [String: Any] {
        guard let items = body["cookies"] as? [Any], items.count <= Self.maxCookiesPerWrite else {
            return errorResponse(code: "INVALID_PARAMS", message: "cookies must be an array of at most \(Self.maxCookiesPerWrite)")
        }
        do {
            let store = try target(body, createPartition: true).store.httpCookieStore
            var written: [(index: Int, cookie: HTTPCookie)] = []
            var failed: [[String: Any]] = []
            for (index, item) in items.enumerated() {
                let json = item as? [String: Any] ?? [:]
                guard let wire = CookieAPIFormat.wireJSON(fromAPI: json),
                      let cookie = SyncCookieWire.httpCookie(from: wire) else {
                    failed.append(Self.failure(index, name: json["name"], domain: json["domain"], "INVALID_COOKIE"))
                    continue
                }
                await store.setCookie(cookie)
                written.append((index, cookie))
            }
            let present = await store.allCookies()
            let missing = written.filter { !Self.stored($0.cookie, in: present) }
            failed += missing.map { Self.failure($0.index, name: $0.cookie.name, domain: $0.cookie.domain, "NOT_STORED") }
            failed.sort { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
            return successResponse(["set": written.count - missing.count, "failed": failed])
        } catch let refusal as Refusal {
            return refusal.response
        } catch {
            return errorResponse(code: "COOKIE_ERROR", message: error.localizedDescription)
        }
    }

    /// Copies every cookie (optionally under `domain`) from one store to another.
    @MainActor
    private func copyCookies(_ body: [String: Any]) async -> [String: Any] {
        if let raw = body["from"], !(raw is [String: Any]) { return errorResponse(code: "INVALID_PARAMS", message: "from must be an object") }
        if let raw = body["to"], !(raw is [String: Any]) { return errorResponse(code: "INVALID_PARAMS", message: "to must be an object") }
        if let raw = body["domain"], !(raw is String) { return errorResponse(code: "INVALID_PARAMS", message: "domain must be a string") }
        do {
            let source = try target(body["from"] as? [String: Any] ?? [:], createPartition: false)
            let destination = try target(body["to"] as? [String: Any] ?? [:], createPartition: true)
            guard !Self.sameStore(source.store, destination.store) else {
                return errorResponse(code: "INVALID_PARAMS", message: "from and to are the same cookie store")
            }
            var cookies = await source.store.httpCookieStore.allCookies()
            if let domain = body["domain"] as? String { cookies = cookies.filter { Self.inDomain($0.domain, domain) } }
            let store = destination.store.httpCookieStore
            for cookie in cookies { await store.setCookie(cookie) }
            let present = await store.allCookies()
            let failed = cookies.enumerated().filter { !Self.stored($0.element, in: present) }.map {
                Self.failure($0.offset, name: $0.element.name, domain: $0.element.domain, "NOT_STORED")
            }
            return successResponse(["copied": cookies.count - failed.count, "failed": failed])
        } catch let refusal as Refusal {
            return refusal.response
        } catch {
            return errorResponse(code: "COOKIE_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func setCookie(_ body: [String: Any]) async -> [String: Any] {
        guard let webView = context.webView,
              let name = body["name"] as? String,
              let value = body["value"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "name and value required")
        }
        let defaultHost = webView.url?.host ?? "localhost"
        guard let cookie = CookieFactory.make(name: name, value: value, body: body, defaultHost: defaultHost) else {
            return errorResponse(code: "COOKIE_ERROR", message: "Failed to create cookie")
        }
        await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        return successResponse()
    }

    @MainActor
    private func deleteCookies(_ body: [String: Any]) async -> [String: Any] {
        guard let webView = context.webView else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        var candidates = await store.allCookies()
        if let url = body["url"] as? String {
            candidates = CookieScope.scoped(candidates, toURL: url)
        }
        let deleteAll = body["deleteAll"] as? Bool ?? false
        let nameFilter = body["name"] as? String
        let domainFilter = body["domain"] as? String

        // No selector supplied: preserve prior behavior (no-op) rather than
        // wiping the store on an empty request.
        guard deleteAll || nameFilter != nil || domainFilter != nil else {
            return successResponse(["deleted": 0])
        }

        // Fast path: wipe everything in scope only when no name/domain filter narrows it.
        if deleteAll && nameFilter == nil && domainFilter == nil {
            for cookie in candidates { await store.deleteCookie(cookie) }
            return successResponse(["deleted": candidates.count])
        }

        var deleted = 0
        for cookie in candidates {
            let matchesName = nameFilter == nil || cookie.name == nameFilter
            let matchesDomain = domainFilter.map { CookieScope.domainMatches(cookie.domain, filter: $0) } ?? true
            if matchesName && matchesDomain {
                await store.deleteCookie(cookie)
                deleted += 1
            }
        }
        return successResponse(["deleted": deleted])
    }
}
