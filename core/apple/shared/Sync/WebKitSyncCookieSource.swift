import Foundation
import WebKit

/// The WebKit default store as a sync source. `getAllCookies` enumerates the whole store,
/// so every snapshot reports `{"all":true}`. Changes are signalled by a cookie-store
/// observer, which also fires for the adapter's own writes.
@MainActor
public final class WebKitSyncCookieSource: SyncCookieSource {
    private let store: WKHTTPCookieStore
    private let observer = Observer()

    public init(store: WKHTTPCookieStore) {
        self.store = store
        store.add(observer)
    }

    deinit {
        let store = store
        let observer = observer
        Task { @MainActor in store.remove(observer) }
    }

    public func snapshot() async throws -> SyncCookieSnapshot {
        let cookies = await store.allCookies()
        return SyncCookieSnapshot(
            cookiesJSON: SyncCookieWire.encode(cookies.compactMap(SyncCookieWire.json(from:))),
            coverageJSON: #"{"all":true}"#
        )
    }

    public func apply(_ op: SyncCookieOp, isCurrent: @escaping @MainActor () -> Bool) async -> SyncCookieOpResult {
        let abandoned = SyncCookieOpResult(id: op.id, ok: false, readbackJSON: "[]")
        guard isCurrent(), let cookie = SyncJSON.object(op.cookieJSON),
              let domain = cookie["domain"] as? String, let name = cookie["name"] as? String else {
            return abandoned
        }
        if op.isDelete {
            let path = cookie["path"] as? String ?? "/"
            for existing in await store.allCookies() where Self.matches(existing, domain: domain, path: path, name: name) {
                guard isCurrent() else { return abandoned }
                await store.deleteCookie(existing)
            }
            return SyncCookieOpResult(id: op.id, ok: true, readbackJSON: await readback(domain: domain, name: name))
        }
        guard let engineCookie = SyncCookieWire.httpCookie(from: cookie) else {
            return SyncCookieOpResult(id: op.id, ok: false, readbackJSON: await readback(domain: domain, name: name))
        }
        guard isCurrent() else { return abandoned }
        await store.setCookie(engineCookie)
        return SyncCookieOpResult(id: op.id, ok: true, readbackJSON: await readback(domain: domain, name: name))
    }

    public func setChangeHandler(_ handler: @escaping @MainActor () -> Void) {
        observer.handler = handler
    }

    /// Every cookie with `name` whose domain, with or without a leading dot, equals the
    /// op's domain without its dot.
    private func readback(domain: String, name: String) async -> String {
        let host = SyncCookieWire.host(of: domain)
        let matching = await store.allCookies().filter { $0.name == name && SyncCookieWire.host(of: $0.domain) == host }
        return SyncCookieWire.encode(matching.compactMap(SyncCookieWire.json(from:)))
    }

    private static func matches(_ cookie: HTTPCookie, domain: String, path: String, name: String) -> Bool {
        cookie.name == name && cookie.domain.lowercased() == domain.lowercased() && (cookie.path.isEmpty ? "/" : cookie.path) == path
    }

    @MainActor
    private final class Observer: NSObject, WKHTTPCookieStoreObserver {
        var handler: (@MainActor () -> Void)?

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            handler?()
        }
    }
}
