@_implementationOnly import KelpieNative
import Foundation

/// One open core-sync store. Every call runs on this actor behind a FIFO gate, so a
/// merge transaction holds the store from plan to commit, including the engine writes
/// between them, and no scan or pull can interleave with it.
actor SyncStoreBridge {
    struct Failure: Error, Equatable {
        let code: String
        let message: String
    }

    typealias Snapshot = @Sendable @MainActor () async throws -> SyncCookieSnapshot
    /// Applies planned ops in order; nil means the account generation changed and the
    /// transaction must be discarded.
    typealias Apply = @Sendable @MainActor ([SyncCookieOp]) async -> [SyncCookieOpResult]?

    nonisolated let replica: String
    private let clock: @Sendable () -> Int64
    private var handle: OpaquePointer?
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(path: String, subject: String, replica: String, launch: Bool, clock: @escaping @Sendable () -> Int64) throws {
        self.replica = replica
        self.clock = clock
        let options = SyncJSON.string([
            "subject": subject, "replica": replica, "launch": launch, "nowMillis": NSNumber(value: clock())
        ] as [String: Any])
        var error: UnsafeMutablePointer<CChar>?
        guard let opened = kelpie_sync_store_open(path, options, &error) else {
            let detail = error.map { String(cString: $0) }.flatMap(SyncJSON.object)
            if let error { kelpie_sync_free_string(error) }
            throw Failure(code: detail?["error"] as? String ?? "STORE_OPEN", message: detail?["message"] as? String ?? "")
        }
        handle = opened
    }

    deinit {
        if let handle { kelpie_sync_store_close(handle) }
    }

    func close() async {
        await exclusive {
            if let handle { kelpie_sync_store_close(handle) }
            handle = nil
        }
    }

    func status() async throws -> [String: Any] {
        try await exclusive { try Self.take(kelpie_sync_store_status(try store())) }
    }

    func finishWarmup() async {
        await exclusive { if let handle { kelpie_sync_store_finish_warmup(handle) } }
    }

    func watermark(_ peer: String) async throws -> [String: Any] {
        try await exclusive { try Self.take(kelpie_sync_store_watermark(try store(), peer)) }
    }

    /// `{"deferred":true}` while warming, else `{"changed","head","purge"}`.
    func scan(_ snapshot: Snapshot) async throws -> [String: Any] {
        try await exclusive {
            let engine = try await snapshot()
            return try Self.take(kelpie_sync_store_scan(try store(), engine.cookiesJSON, engine.coverageJSON, clock()))
        }
    }

    /// The default store moved to another engine: adopt its cookies as observed state,
    /// stamping and tombstoning nothing. `{"adopted","head"}`.
    func rebase(_ snapshot: Snapshot) async throws -> [String: Any] {
        try await exclusive {
            let engine = try await snapshot()
            return try Self.take(kelpie_sync_store_rebase(try store(), engine.cookiesJSON, engine.coverageJSON, clock()))
        }
    }

    func answerPull(_ pull: [String: Any], snapshot: Snapshot) async throws -> [String: Any] {
        try await exclusive {
            let engine = try await snapshot()
            return try Self.take(kelpie_sync_store_answer_pull(
                try store(), SyncJSON.string(pull), engine.cookiesJSON, engine.coverageJSON, clock()
            ))
        }
    }

    func buildPush(watermark: [String: Any], snapshot: Snapshot) async throws -> [String: Any] {
        try await exclusive {
            let engine = try await snapshot()
            return try Self.take(kelpie_sync_store_build_push(
                try store(), SyncJSON.string(watermark), engine.cookiesJSON, engine.coverageJSON, clock()
            ))
        }
    }

    /// Plan, engine writes, commit. Returns the number of applied ops. The source
    /// watermark moves only when the commit succeeds.
    func merge(records: [Any], source: [String: Any], apply: Apply) async throws -> Int {
        try await exclusive {
            let plan = try Self.take(kelpie_sync_store_plan_merge(
                try store(), SyncJSON.string(records), SyncJSON.string(source), clock()
            ))
            let ops = (plan["ops"] as? [[String: Any]] ?? []).compactMap(Self.op)
            guard let results = await apply(ops), results.count == ops.count else {
                if let handle { kelpie_sync_store_abort_merge(handle) }
                throw CancellationError()
            }
            let encoded: [[String: Any]] = results.map {
                ["id": $0.id, "ok": $0.ok, "readback": SyncJSON.value($0.readbackJSON) as? [Any] ?? []]
            }
            let committed = try Self.take(kelpie_sync_store_commit_merge(try store(), SyncJSON.string(encoded)))
            return committed["applied"] as? Int ?? 0
        }
    }

    // MARK: - Stateless helpers

    /// nil when the message is well formed, otherwise core-sync's reason.
    nonisolated static func invalidReason(_ kind: String, _ message: [String: Any]) -> String? {
        guard let result = try? take(kelpie_sync_validate(kind, SyncJSON.string(message))) else { return "invalid" }
        return result["ok"] as? Bool == true ? nil : result["error"] as? String ?? "invalid"
    }

    nonisolated static func challenge(initiator: [String: String], responder: [String: String]) throws -> String {
        let pair = SyncJSON.string(["initiator": initiator, "responder": responder])
        guard let challenge = try take(kelpie_sync_transcript(pair))["challenge"] as? String else {
            throw Failure(code: "INVALID_MESSAGE", message: "no challenge")
        }
        return challenge
    }

    nonisolated static func accountHints(subject: String, now: Int64) throws -> (current: String, accepted: Set<String>) {
        let result = try take(kelpie_sync_account_hints(subject, now))
        guard let current = result["current"] as? String, let accepted = result["accepted"] as? [String] else {
            throw Failure(code: "INVALID_OPTIONS", message: "no hints")
        }
        return (current, Set(accepted))
    }

    // MARK: - Gate

    private func exclusive<T>(_ body: () async throws -> T) async rethrows -> T {
        await enter()
        defer { leave() }
        return try await body()
    }

    private func enter() async {
        guard held else {
            held = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Hands the gate straight to the next waiter, so ownership never lapses.
    private func leave() {
        if waiters.isEmpty { held = false } else { waiters.removeFirst().resume() }
    }

    private func store() throws -> OpaquePointer {
        guard let handle else { throw Failure(code: "NO_STORE", message: "store is closed") }
        return handle
    }

    private static func op(_ planned: [String: Any]) -> SyncCookieOp? {
        guard let id = planned["id"] as? Int, let kind = planned["op"] as? String, let cookie = planned["cookie"] else { return nil }
        return SyncCookieOp(id: id, isDelete: kind == "delete", cookieJSON: SyncJSON.string(cookie))
    }

    private static func take(_ raw: UnsafeMutablePointer<CChar>?) throws -> [String: Any] {
        guard let raw else { throw Failure(code: "INTERNAL", message: "no result") }
        defer { kelpie_sync_free_string(raw) }
        guard let object = SyncJSON.object(String(cString: raw)) else {
            throw Failure(code: "INVALID_JSON", message: "result is not an object")
        }
        if let code = object["error"] as? String { throw Failure(code: code, message: object["message"] as? String ?? "") }
        return object
    }
}
