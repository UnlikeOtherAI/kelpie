#if !KELPIE_WEBKIT_ONLY
@_implementationOnly import KelpieChromium
import Foundation

/// Chromium's one cookie store: CEF's global cookie manager. Needs no browser view and
/// reads and writes HttpOnly cookies with their real attributes.
@MainActor
enum CEFGlobalCookies {
    struct Unavailable: Error {}
    struct Incomplete: Error { let seen: [BrowserCookie] }

    static var isAvailable: Bool { CEFBridge.isGlobalCookieStoreAvailable() }

    /// Every cookie, from a visit CEF finished. Throws instead of returning a partial store.
    static func all() async throws -> [BrowserCookie] {
        guard isAvailable else { throw Unavailable() }
        let (complete, dicts) = await withCheckedContinuation { continuation in
            CEFBridge.visitGlobalCookies { complete, cookies in
                continuation.resume(returning: (complete, cookies))
            }
        }
        let cookies = dicts.compactMap { BrowserCookie(bridge: $0) }
        guard complete else { throw Incomplete(seen: cookies) }
        return cookies
    }

    /// Whether CEF accepted and stored the cookie.
    static func set(_ cookie: BrowserCookie) async -> Bool {
        guard isAvailable, let dict = cookie.bridgeDictionary else { return false }
        return await withCheckedContinuation { continuation in
            CEFBridge.setGlobalCookie(dict) { continuation.resume(returning: $0) }
        }
    }

    /// Sets many cookies concurrently and returns one result per cookie, in order.
    static func set(_ cookies: [BrowserCookie]) async -> [Bool] {
        await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, cookie) in cookies.enumerated() {
                group.addTask { @MainActor in (index, await set(cookie)) }
            }
            var results = [Bool](repeating: false, count: cookies.count)
            for await (index, ok) in group { results[index] = ok }
            return results
        }
    }

    /// Deletes exactly these keys in one visit and returns how many cookies went.
    @discardableResult
    static func delete(_ keys: [BrowserCookie.Key]) async throws -> Int {
        guard isAvailable else { throw Unavailable() }
        guard !keys.isEmpty else { return 0 }
        let payload = keys.map { ["domain": $0.domain, "path": $0.path, "name": $0.name] }
        let (complete, deleted) = await withCheckedContinuation { continuation in
            CEFBridge.deleteGlobalCookies(matching: payload) { complete, deleted in
                continuation.resume(returning: (complete, deleted))
            }
        }
        guard complete else { throw Incomplete(seen: []) }
        return deleted
    }

    static func deleteAll() async throws {
        guard isAvailable else { throw Unavailable() }
        let success = await withCheckedContinuation { continuation in
            CEFBridge.deleteAllGlobalCookies { success, _ in continuation.resume(returning: success) }
        }
        guard success else { throw Incomplete(seen: []) }
    }
}
#endif
