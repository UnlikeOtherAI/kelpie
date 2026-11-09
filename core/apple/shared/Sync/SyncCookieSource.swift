import Foundation

/// One read of the default cookie store in core-sync's wire shape.
/// `coverageJSON` is `{"all":true}` only when the whole store was enumerated.
public struct SyncCookieSnapshot: Sendable {
    public let cookiesJSON: String
    public let coverageJSON: String

    public init(cookiesJSON: String, coverageJSON: String) {
        self.cookiesJSON = cookiesJSON
        self.coverageJSON = coverageJSON
    }
}

/// One engine write planned by core-sync. `cookieJSON` is a full wire cookie for a
/// set and `{"domain","path","name"}` for a delete.
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

/// The outcome of one op. `readbackJSON` is a JSON array of every cookie the engine
/// holds with the op's name for its domain, with or without a leading dot.
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

/// The default cookie store as the sync service sees it. Partitioned stores never
/// implement this. A failed or partial read must throw rather than return less.
@MainActor public protocol SyncCookieSource: AnyObject {
    func snapshot() async throws -> SyncCookieSnapshot
    func apply(_ op: SyncCookieOp) async -> SyncCookieOpResult
    func setChangeHandler(_ handler: @escaping @MainActor () -> Void)
}
