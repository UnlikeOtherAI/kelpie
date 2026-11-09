// TEMPORARY: a stand-in for the shared sync service in core/apple/shared/Sync, which is
// being written on claude/p2p-sync-apple-20261109. It matches that branch's interface so the
// macOS adapter compiles and can be tested on its own. Deleted once that branch is used.
import Foundation
import WebKit

public struct SyncCookieSnapshot: Sendable {
    public let cookiesJSON: String
    public let coverageJSON: String

    public init(cookiesJSON: String, coverageJSON: String) {
        self.cookiesJSON = cookiesJSON
        self.coverageJSON = coverageJSON
    }
}

public struct SyncCookieOp: Sendable {
    public let id: Int
    public let isDelete: Bool
    public let cookieJSON: String

    public init(id: Int, isDelete: Bool, cookieJSON: String) {
        self.id = id
        self.isDelete = isDelete
        self.cookieJSON = cookieJSON
    }
}

public struct SyncCookieOpResult: Sendable {
    public let id: Int
    public let ok: Bool
    public let readbackJSON: String

    public init(id: Int, ok: Bool, readbackJSON: String) {
        self.id = id
        self.ok = ok
        self.readbackJSON = readbackJSON
    }
}

@MainActor public protocol SyncCookieSource: AnyObject {
    func snapshot() async throws -> SyncCookieSnapshot
    func apply(_ op: SyncCookieOp) async -> SyncCookieOpResult
    func setChangeHandler(_ handler: @escaping @MainActor () -> Void)
}

/// TEMPORARY: the shared source delegates to core-sync's wire conversion.
@MainActor
public final class WebKitSyncCookieSource: SyncCookieSource {
    private let store: WKHTTPCookieStore

    public init(store: WKHTTPCookieStore) {
        self.store = store
    }

    public func snapshot() async throws -> SyncCookieSnapshot {
        SyncCookieSnapshot(cookiesJSON: MacSyncCookieSource.text(try await CookieJar.webKit(store).all()), coverageJSON: #"{"all":true}"#)
    }

    public func apply(_ op: SyncCookieOp) async -> SyncCookieOpResult {
        await MacSyncCookieSource.apply(op, to: .webKit(store))
    }

    public func setChangeHandler(_ handler: @escaping @MainActor () -> Void) {}
}

@MainActor
protocol SyncAccount: AnyObject {}

@MainActor
final class UOASyncAccount: SyncAccount {}

struct SyncEnvironment {
    var platform: String
    var deviceName: String
}

@MainActor
final class CookieSyncService {
    private let account: SyncAccount
    private let source: SyncCookieSource
    private let environment: SyncEnvironment
    private var started = false

    init(account: SyncAccount, source: SyncCookieSource, environment: SyncEnvironment) {
        self.account = account
        self.source = source
        self.environment = environment
    }

    func start() { started = true }
    func stop() { started = false }

    func status() async -> [String: Any] {
        ["supported": true, "signedIn": UOAAccount.shared.profile != nil, "listening": false,
         "peers": [[String: Any]](), "store": [String: Any]()]
    }
}
