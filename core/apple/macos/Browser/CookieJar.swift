#if !KELPIE_WEBKIT_ONLY
@_implementationOnly import KelpieChromium
#endif
import Foundation
import WebKit

/// One cookie store: a WebKit store (the default store or a partition's) or Chromium's
/// global store. Reads are complete or throw; nothing here reports a partial store as whole.
@MainActor
enum CookieJar {
    case webKit(WKHTTPCookieStore)
    #if !KELPIE_WEBKIT_ONLY
    case chromium
    #endif

    func all() async throws -> [BrowserCookie] {
        switch self {
        case .webKit(let store):
            return await store.allCookies().map(BrowserCookie.init)
        #if !KELPIE_WEBKIT_ONLY
        case .chromium:
            return try await CEFGlobalCookies.all()
        #endif
        }
    }

    /// Writes the cookies concurrently and returns, per cookie, whether the engine took it.
    /// WebKit gives no per-write result, so a WebKit write counts only once a read finds it.
    func set(_ cookies: [BrowserCookie]) async -> [Bool] {
        guard !cookies.isEmpty else { return [] }
        switch self {
        case .webKit(let store):
            let written: [Bool] = await withTaskGroup(of: (Int, Bool).self) { group in
                for (index, cookie) in cookies.enumerated() {
                    group.addTask { @MainActor in
                        guard let httpCookie = cookie.httpCookie else { return (index, false) }
                        await store.setCookie(httpCookie)
                        return (index, true)
                    }
                }
                var results = [Bool](repeating: false, count: cookies.count)
                for await (index, ok) in group { results[index] = ok }
                return results
            }
            let stored = Dictionary(await store.allCookies().map(BrowserCookie.init).map { ($0.key, $0.value) },
                                    uniquingKeysWith: { _, last in last })
            return zip(cookies, written).map { cookie, ok in ok && stored[cookie.key] == cookie.value }
        #if !KELPIE_WEBKIT_ONLY
        case .chromium:
            return await CEFGlobalCookies.set(cookies)
        #endif
        }
    }

    /// Deletes exactly these keys and returns how many cookies were removed.
    @discardableResult
    func delete(_ keys: [BrowserCookie.Key]) async throws -> Int {
        guard !keys.isEmpty else { return 0 }
        switch self {
        case .webKit(let store):
            let wanted = Set(keys)
            let doomed = await store.allCookies().filter { wanted.contains(BrowserCookie($0).key) }
            for cookie in doomed { await store.deleteCookie(cookie) }
            return doomed.count
        #if !KELPIE_WEBKIT_ONLY
        case .chromium:
            return try await CEFGlobalCookies.delete(keys)
        #endif
        }
    }

    func deleteAll() async throws {
        switch self {
        case .webKit(let store):
            for cookie in await store.allCookies() { await store.deleteCookie(cookie) }
        #if !KELPIE_WEBKIT_ONLY
        case .chromium:
            try await CEFGlobalCookies.deleteAll()
        #endif
        }
    }

    /// The read-back contract: every cookie named `name` whose domain, with or without a
    /// leading dot, equals `domain` without its dot.
    static func readback(_ cookies: [BrowserCookie], name: String, domain: String) -> [BrowserCookie] {
        let bare = BrowserCookie.bare(domain)
        return cookies.filter { $0.name == name && $0.bareDomain == bare }
    }
}

/// Copies one store's cookies into another. Never transfers values through the caller.
@MainActor
enum CookieCopier {
    struct Report: Equatable {
        var copied = 0
        var failed: [BrowserCookie.Key] = []
        /// Partitioned cookies, which are never copied.
        var partitioned: [BrowserCookie.Key] = []
        var sourceUnreadable = false
    }

    /// Adds or updates `cookies` in `target`, skipping those it already holds unchanged.
    static func copy(_ cookies: [BrowserCookie], into target: CookieJar, existing: [BrowserCookie]?) async -> Report {
        let current = Dictionary((existing ?? []).map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        var report = Report(partitioned: cookies.filter(\.partitioned).map(\.key))
        let copyable = cookies.filter { !$0.partitioned }
        let pending = copyable.filter { current[$0.key] != $0 }
        let results = await target.set(pending)
        for (cookie, ok) in zip(pending, results) {
            if ok { report.copied += 1 } else { report.failed.append(cookie.key) }
        }
        report.copied += copyable.count - pending.count
        return report
    }

    /// Copies every cookie `source` holds into `target`. Cookies only `target` holds are
    /// kept: they may be the only copy of a login made while that engine was live.
    static func copyAll(from source: CookieJar, to target: CookieJar) async -> Report {
        let cookies: [BrowserCookie]
        do { cookies = try await source.all() } catch { return Report(sourceUnreadable: true) }
        return await copy(cookies, into: target, existing: try? await target.all())
    }
}
