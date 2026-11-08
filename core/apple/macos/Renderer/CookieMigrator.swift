import Foundation

/// Migrates cookies from one renderer engine to another.
/// Called during renderer switches to preserve login sessions.
@MainActor
enum CookieMigrator {
    static func migrate(from source: any RendererEngine, to target: any RendererEngine) async {
        guard source.engineName != "chromium" else {
            let snapshot = SharedCookieJar.load()
            guard !snapshot.cookies.isEmpty else { return }
            await target.setCookies(snapshot.cookies)
            return
        }
        let cookies = await source.allCookies()
        guard !cookies.isEmpty else { return }
        await target.setCookies(cookies)
    }
}
