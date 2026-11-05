import Foundation

/// Only authenticated HTTP/MCP dispatch may install the grant in task context.
struct IOSScriptGrant: Sendable {
    @TaskLocal static var current: Self?

    let owner: String
    let isCurrent: @Sendable () async -> Bool

    init(listener: UUID, clientID: String, bearer: String, isCurrent: @escaping @Sendable () async -> Bool) {
        // Include grant and listener incarnation, so re-pairing a named client cannot inherit a run.
        let digest = PairingStore.hashToken(bearer)
        self.owner = listener.uuidString + ":" + digest + ":" + clientID
        self.isCurrent = isCurrent
    }
}

struct IOSWorkflowFailure: Error {
    let code: String
    let mayHaveCompleted: Bool

    init(_ code: String, mayHaveCompleted: Bool = false) {
        self.code = code
        self.mayHaveCompleted = mayHaveCompleted
    }

    var response: [String: Any] {
        var result = errorResponse(code: code, message: "Workflow stopped at its last confirmed step")
        if mayHaveCompleted { result["mayHaveCompleted"] = true }
        return result
    }
}

/// Tracks server lifetime without retaining the server or exposing authentication material.
final class IOSScriptListener: @unchecked Sendable {
    private let lock = NSLock()
    private var active: UUID?

    func start() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID()
        active = id
        return id
    }

    func stop(_ expected: UUID? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if expected == nil || expected == active { active = nil }
    }

    var incarnation: UUID? {
        lock.lock()
        defer { lock.unlock() }
        return active
    }
}
