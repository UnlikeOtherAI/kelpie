import Foundation

/// `set-cookies`, `copy-cookies` and `get-cookie-sync-status`.
///
/// A store is named by `{tabId?, partition?}`: a tab's store, a partition's store, or the
/// live default store when both are absent. Writing the default store syncs like any other
/// change. `copy-cookies` moves values inside the browser; they never reach the caller.
extension BrowserManagementHandler {
    enum CookieTargetResolution {
        case target(HandlerContext.CookieTarget)
        case failure([String: Any])
    }

    @MainActor
    func setCookies(_ body: [String: Any]) async -> [String: Any] {
        guard let items = body["cookies"] as? [Any] else {
            return errorResponse(code: "INVALID_PARAMS", message: "cookies must be an array")
        }
        guard items.count <= CookieRequest.maxImportCount else {
            return errorResponse(code: "INVALID_PARAMS", message: "cookies holds at most \(CookieRequest.maxImportCount) entries")
        }
        let target: HandlerContext.CookieTarget
        switch resolveCookieTarget(body) {
        case .target(let resolved): target = resolved
        case .failure(let response): return response
        }

        var failed: [[String: Any]] = []
        var accepted: [(index: Int, cookie: BrowserCookie)] = []
        for (index, item) in items.enumerated() {
            switch CookieRequest.cookie(from: item) {
            case .success(let cookie): accepted.append((index, cookie))
            case .failure(let reason):
                let dict = item as? [String: Any]
                failed.append(CookieRequest.failure(index: index, name: dict?["name"], domain: dict?["domain"], error: reason.rawValue))
            }
        }
        let results: [Bool]
        do {
            results = try await context.withCookies(target) { await $0.set(accepted.map(\.cookie)) }
        } catch {
            return Self.cookieStoreUnavailable()
        }
        for (entry, ok) in zip(accepted, results) where !ok {
            let error = CookieRequest.CookieError.refused.rawValue
            failed.append(CookieRequest.failure(index: entry.index, name: entry.cookie.name, domain: entry.cookie.domain, error: error))
        }
        failed.sort { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
        return successResponse(["set": results.filter { $0 }.count, "failed": failed])
    }

    @MainActor
    func copyCookies(_ body: [String: Any]) async -> [String: Any] {
        guard body["from"] == nil || body["from"] is [String: Any], body["to"] == nil || body["to"] is [String: Any] else {
            return errorResponse(code: "INVALID_PARAMS", message: "from and to must be objects")
        }
        if let invalid = Self.invalidCookieField(body, strings: ["domain"]) { return invalid }
        let source: HandlerContext.CookieTarget
        let destination: HandlerContext.CookieTarget
        switch (resolveCookieTarget(body["from"] as? [String: Any] ?? [:]),
                resolveCookieTarget(body["to"] as? [String: Any] ?? [:])) {
        case (.failure(let response), _), (_, .failure(let response)):
            return response
        case let (.target(from), .target(to)):
            source = from
            destination = to
        }
        guard source.identity != destination.identity else {
            return errorResponse(code: "INVALID_PARAMS", message: "from and to name the same cookie store")
        }
        do {
            var cookies = try await context.withCookies(source) { try await $0.all() }
            if let domain = body["domain"] as? String { cookies = cookies.filter { CookieRequest.domain($0, matches: domain) } }
            let report = try await context.withCookies(destination) { jar in
                await CookieCopier.copy(cookies, into: jar, existing: try? await jar.all())
            }
            let failed = report.failed.map { Self.copyFailure($0, CookieRequest.CookieError.refused) } +
                report.partitioned.map { Self.copyFailure($0, CookieRequest.CookieError.partitioned) }
            return successResponse(["copied": report.copied, "failed": failed])
        } catch {
            return Self.cookieStoreUnavailable()
        }
    }

    @MainActor
    func getCookieSyncStatus(_ body: [String: Any]) async -> [String: Any] {
        guard let sync = context.cookieSync else { return successResponse(MacCookieSync.unavailableStatus()) }
        return successResponse(await sync.status())
    }

    private static func copyFailure(_ key: BrowserCookie.Key, _ error: CookieRequest.CookieError) -> [String: Any] {
        ["name": key.name, "domain": key.domain, "path": key.path, "error": error.rawValue]
    }

    /// Resolves `{tabId?, partition?}` to one store, keeping today's tab lease rules.
    @MainActor
    func resolveCookieTarget(_ selector: [String: Any]) -> CookieTargetResolution {
        if let invalid = Self.invalidCookieField(selector, strings: ["tabId", "partition"]) { return .failure(invalid) }
        let tabId = selector["tabId"] as? String
        let partition = selector["partition"] as? String
        if tabId != nil && partition != nil {
            return .failure(errorResponse(code: "INVALID_PARAMS", message: "Name a tabId or a partition, not both"))
        }
        if let partition { return resolvePartitionCookieTarget(partition) }
        guard let tabId else { return .target(context.defaultCookieTarget) }
        do {
            return .target(context.cookieTarget(for: try context.resolveRenderer(tabId: tabId)))
        } catch {
            return .failure(tabErrorResponse(from: error) ?? errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription))
        }
    }

    /// An existing partition's store. Partitions are WebKit stores, so Chromium refuses them.
    @MainActor
    private func resolvePartitionCookieTarget(_ id: String) -> CookieTargetResolution {
        if let unsupported = chromiumUnsupportedIfActive() { return .failure(unsupported) }
        if let reason = PartitionValidator.validate(id) {
            return .failure(errorResponse(code: "INVALID_PARTITION", message: "Invalid partition \"\(id)\": \(reason.message)"))
        }
        guard let resolved = PartitionRegistry.shared.rebind(id: id) else {
            return .failure(errorResponse(
                code: "PARTITION_NOT_FOUND",
                message: "No partition \"\(id)\". Open a tab in it with new-tab, or list partitions with get-partitions."
            ))
        }
        return .target(HandlerContext.CookieTarget(
            jar: .webKit(resolved.dataStore.httpCookieStore), partition: resolved.id, identity: "partition:\(resolved.id)"
        ))
    }
}
