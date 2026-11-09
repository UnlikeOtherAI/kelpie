import AppKit
import Foundation

/// Runs peer-to-peer cookie sync for the standalone macOS app. The shared service follows
/// the UOA account itself: it opens a run on sign-in or a restored session (`launch:true`
/// only for the first store opened in this process) and tears it down on sign-out or an
/// account change. Closing the session stops it. Embedded hosts never create one.
@MainActor
final class MacCookieSync {
    let source: MacSyncCookieSource
    private let service: CookieSyncService

    init(defaultCookies: DefaultCookieStore) {
        source = MacSyncCookieSource(store: defaultCookies, webKitStore: KelpieWebsiteData.store.httpCookieStore)
        let environment = SyncEnvironment(platform: "macos", deviceName: Host.current().localizedName ?? "Mac")
        service = CookieSyncService(account: UOASyncAccount(), source: source, environment: environment)
    }

    func start() {
        service.start()
    }

    func close() {
        service.stop()
        source.detach()
    }

    /// The default store moved to the other engine. The spec makes this a rebase: refresh
    /// what sync has observed from the new engine, stamping and tombstoning nothing. The
    /// shared service has no rebase call yet, so nothing happens here until it does.
    func rendererDidSwitch() {}

    func status() async -> [String: Any] {
        await service.status()
    }

    /// The status of a session that never syncs, in the service's shape.
    static func unavailableStatus() -> [String: Any] {
        [
            "supported": false, "reason": "EMBEDDED_SESSION", "signedIn": UOAAccount.shared.profile != nil,
            "listening": false, "peers": [[String: Any]](), "store": [String: Any]()
        ]
    }
}
