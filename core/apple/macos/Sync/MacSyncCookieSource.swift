import Foundation
import WebKit

/// The sync service's view of the live default store on macOS: WebKit's default store
/// while WebKit renders, Chromium's global cookie manager while Chromium renders.
///
/// Every snapshot and write runs inside `DefaultCookieStore.exclusive`, so a renderer
/// switch never interleaves with a sync write and its read-back.
@MainActor
final class MacSyncCookieSource: SyncCookieSource {
    static let chromiumScanInterval: TimeInterval = 15

    private let store: DefaultCookieStore
    private let webKit: WebKitSyncCookieSource
    private var changeHandler: (@MainActor () -> Void)?
    private var chromiumTimer: Timer?
    private var chromiumLoadObserver: NSObjectProtocol?

    init(store: DefaultCookieStore, webKitStore: WKHTTPCookieStore) {
        self.store = store
        webKit = WebKitSyncCookieSource(store: webKitStore)
    }

    func snapshot() async throws -> SyncCookieSnapshot {
        try await store.exclusive { jar in
            switch jar {
            case .webKit:
                return try await webKit.snapshot()
            #if !KELPIE_WEBKIT_ONLY
            case .chromium:
                // Only a finished full visit is `all`; a partial visit throws and aborts the scan.
                let cookies = try await CEFGlobalCookies.all()
                return SyncCookieSnapshot(cookiesJSON: Self.text(cookies), coverageJSON: #"{"all":true}"#)
            #endif
            }
        }
    }

    func apply(_ op: SyncCookieOp, isCurrent: @escaping @MainActor () -> Bool) async -> SyncCookieOpResult {
        await store.exclusive { jar in
            // The exclusive gate may have waited: re-check before any write.
            guard isCurrent() else { return SyncCookieOpResult(id: op.id, ok: false, readbackJSON: "[]") }
            switch jar {
            case .webKit:
                return await webKit.apply(op, isCurrent: isCurrent)
            #if !KELPIE_WEBKIT_ONLY
            case .chromium:
                return await Self.apply(op, to: jar)
            #endif
            }
        }
    }

    func setChangeHandler(_ handler: @escaping @MainActor () -> Void) {
        changeHandler = handler
        webKit.setChangeHandler { [weak self] in
            guard let self, self.store.engine == .webkit else { return }
            self.changeHandler?()
        }
        startChromiumSignals()
    }

    /// Stops every change signal; the service that owned the handler has stopped.
    func detach() {
        changeHandler = nil
        webKit.setChangeHandler {}
        chromiumTimer?.invalidate()
        chromiumTimer = nil
        if let chromiumLoadObserver { NotificationCenter.default.removeObserver(chromiumLoadObserver) }
        chromiumLoadObserver = nil
    }

    /// Chromium has no cookie observer: a finished page load and a 15 s timer stand in.
    private func startChromiumSignals() {
        chromiumTimer?.invalidate()
        chromiumTimer = Timer.scheduledTimer(withTimeInterval: Self.chromiumScanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.signalChromiumChange() }
        }
        if chromiumLoadObserver == nil {
            chromiumLoadObserver = NotificationCenter.default.addObserver(
                forName: .kelpieChromiumDocumentLoaded, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.signalChromiumChange() }
            }
        }
    }

    private func signalChromiumChange() {
        guard store.engine == .chromium else { return }
        changeHandler?()
    }

    /// Writes one op, then reads back every cookie with the op's name on its bare domain.
    /// A failed write or read-back reports `ok: false` with whatever the engine still holds.
    static func apply(_ op: SyncCookieOp, to jar: CookieJar) async -> SyncCookieOpResult {
        guard let data = op.cookieJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cookie = BrowserCookie(syncWire: dict) else {
            return SyncCookieOpResult(id: op.id, ok: false, readbackJSON: "[]")
        }
        let wrote: Bool
        if op.isDelete {
            wrote = (try? await jar.delete([cookie.key])) != nil
        } else {
            wrote = await jar.set([cookie]).first ?? false
        }
        do {
            let readback = CookieJar.readback(try await jar.all(), name: cookie.name, domain: cookie.domain)
            return SyncCookieOpResult(id: op.id, ok: wrote, readbackJSON: text(readback))
        } catch {
            #if !KELPIE_WEBKIT_ONLY
            if let incomplete = error as? CEFGlobalCookies.Incomplete {
                let seen = CookieJar.readback(incomplete.seen, name: cookie.name, domain: cookie.domain)
                return SyncCookieOpResult(id: op.id, ok: false, readbackJSON: text(seen))
            }
            #endif
            return SyncCookieOpResult(id: op.id, ok: false, readbackJSON: "[]")
        }
    }

    /// Engine cookies in the core-sync wire shape. A cookie whose SameSite the engine could
    /// not name is skipped: unknown never becomes a default.
    static func text(_ cookies: [BrowserCookie]) -> String {
        let wire = cookies.compactMap(\.syncWireJSON)
        guard let data = try? JSONSerialization.data(withJSONObject: wire) else { return "[]" }
        return String(bytes: data, encoding: .utf8) ?? "[]"
    }
}
