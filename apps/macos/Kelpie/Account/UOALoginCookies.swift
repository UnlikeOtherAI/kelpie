import Foundation
import WebKit

/// The UOA login always runs in WebKit's default store, the one unpartitioned WebKit tabs use.
/// Chromium keeps its own cookie store, so while Chromium is the active engine the login first
/// borrows Chromium's cookies (reusing an existing Google session) and afterwards hands back every
/// cookie the login created or changed. The engine-switch path (`CookieMigrator`) uses the same
/// renderer cookie APIs.
@MainActor
enum UOALoginCookies {
    /// Installed at launch; the source of the active renderer.
    static weak var context: HandlerContext?

    /// Seeds the login store from an active Chromium renderer and returns the store's cookies
    /// afterwards, the baseline `share(changesSince:)` compares against.
    static func prepare() async -> [HTTPCookie] {
        let store = WKWebsiteDataStore.default().httpCookieStore
        if let renderer = chromiumRenderer() {
            for cookie in await renderer.allCookies() {
                await store.setCookie(cookie)
            }
        }
        return await store.allCookies()
    }

    /// Sets the cookies the login created or changed into the active Chromium renderer, if any.
    /// WebKit tabs already share the login store and need nothing.
    static func share(changesSince baseline: [HTTPCookie]) async {
        guard let renderer = chromiumRenderer() else { return }
        let current = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let changed = changes(from: baseline, to: current)
        guard !changed.isEmpty else { return }
        await renderer.setCookies(changed)
    }

    /// Cookies in `after` that are new or differ from their `before` counterpart (same name, domain and path).
    nonisolated static func changes(from before: [HTTPCookie], to after: [HTTPCookie]) -> [HTTPCookie] {
        let previous = Dictionary(before.map { (identity($0), fingerprint($0)) }, uniquingKeysWith: { _, last in last })
        return after.filter { previous[identity($0)] != fingerprint($0) }
    }

    /// The active renderer when it is Chromium and shares the default (unpartitioned) cookie jar.
    private static func chromiumRenderer() -> (any RendererEngine)? {
        guard let context, let renderer = context.renderer, renderer.engineName == "chromium",
              !context.activeRendererIsPartitioned else { return nil }
        return renderer
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
