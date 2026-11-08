import Foundation

/// A cached store belongs to one browser profile. Retained old work keeps its old instance.
final class KelpieProfileValue<Value>: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var current: (profile: String, value: Value)?

    func get(_ create: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        let profile = KelpieStorage.profileID
        if let current, current.profile == profile { return current.value }
        let value = create()
        current = (profile, value)
        return value
    }
}
