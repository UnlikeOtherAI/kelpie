import Foundation

/// Only normally authenticated transports establish this task-local grant.
struct ScriptRequestOwner: Sendable {
    @TaskLocal static var current: Self?
    let owner: String
    let isCurrent: @Sendable () async -> Bool

    init(listener: UUID, clientID: String, bearer: String, isCurrent: @escaping @Sendable () async -> Bool) {
        owner = listener.uuidString + ":" + PairingStore.hashToken(bearer) + ":" + clientID
        self.isCurrent = isCurrent
    }
}

/// Listener incarnations retire on stop/restart without retaining the HTTP server.
final class ScriptListenerScope: @unchecked Sendable {
    private let lock = NSLock()
    private var active: UUID?

    func start() -> UUID {
        lock.withLock {
            let id = UUID()
            active = id
            return id
        }
    }

    func stop(_ expected: UUID? = nil) {
        lock.withLock {
            if expected == nil || expected == active { active = nil }
        }
    }

    var incarnation: UUID? { lock.withLock { active } }
}
