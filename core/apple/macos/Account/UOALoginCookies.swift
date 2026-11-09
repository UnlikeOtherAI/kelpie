import Foundation
import WebKit

/// The UOA login always runs in WebKit's default store, the one unpartitioned WebKit tabs use.
/// While Chromium is the live default store, the login first borrows Chromium's cookies (reusing
/// an existing Google session) and afterwards hands back every cookie the login created or
/// changed. Both directions go through `DefaultCookieStore`, the path sync and renderer switches use.
@MainActor
enum UOALoginCookies {
    /// Installed at launch; the source of the live default store.
    static weak var context: HandlerContext?

    /// Seeds the login store from Chromium when it is live and returns the store's cookies
    /// afterwards, the baseline `share(changesSince:)` compares against.
    static func prepare() async -> [HTTPCookie] {
        let store = KelpieWebsiteData.store.httpCookieStore
        if let defaultCookies = chromiumDefaultStore(),
           let cookies = try? await defaultCookies.exclusive({ try await $0.all() }) {
            _ = await CookieJar.webKit(store).set(cookies)
        }
        return await store.allCookies()
    }

    /// Sets the cookies the login created or changed into Chromium when it is live.
    /// WebKit tabs already share the login store and need nothing.
    static func share(changesSince baseline: [HTTPCookie]) async {
        guard let defaultCookies = chromiumDefaultStore() else { return }
        let current = await KelpieWebsiteData.store.httpCookieStore.allCookies()
        let changed = changes(from: baseline, to: current).map(BrowserCookie.init)
        guard !changed.isEmpty else { return }
        _ = await defaultCookies.exclusive { jar in
            // The engine may have switched while the login ran; WebKit then needs nothing.
            guard case .webKit = jar else { return await jar.set(changed) }
            return []
        }
    }

    /// Cookies in `after` that are new or differ from their `before` counterpart (same name, domain and path).
    nonisolated static func changes(from before: [HTTPCookie], to after: [HTTPCookie]) -> [HTTPCookie] {
        let previous = Dictionary(before.map { (identity($0), fingerprint($0)) }, uniquingKeysWith: { _, last in last })
        return after.filter { previous[identity($0)] != fingerprint($0) }
    }

    /// The live default store when Chromium renders it.
    private static func chromiumDefaultStore() -> DefaultCookieStore? {
        guard let context, context.defaultCookies.engine == .chromium else { return nil }
        return context.defaultCookies
    }

    nonisolated private static func identity(_ cookie: HTTPCookie) -> String {
        [cookie.name, cookie.domain.lowercased(), cookie.path].joined(separator: "\u{1F}")
    }

    nonisolated private static func fingerprint(_ cookie: HTTPCookie) -> String {
        [
            cookie.value,
            cookie.expiresDate?.timeIntervalSince1970.description ?? "",
            cookie.isHTTPOnly ? "1" : "0",
            cookie.isSecure ? "1" : "0",
            cookie.sameSitePolicy?.rawValue ?? ""
        ].joined(separator: "\u{1F}")
    }
}
