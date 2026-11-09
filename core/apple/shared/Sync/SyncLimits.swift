import Foundation

/// Sliding one-minute limits: per key and in total.
struct SyncRateLimiter {
    let perKey: Int
    let total: Int
    var window: TimeInterval = 60
    private var events: [(key: String, at: Date)] = []

    init(perKey: Int, total: Int) {
        self.perKey = perKey
        self.total = total
    }

    /// Records the event and returns true when it is within both limits.
    mutating func allow(_ key: String, now: Date = Date()) -> Bool {
        events.removeAll { now.timeIntervalSince($0.at) >= window }
        guard events.count < total, events.lazy.filter({ $0.key == key }).count < perKey else { return false }
        events.append((key, now))
        return true
    }

    /// When the next event would be allowed in total.
    func nextSlot(now: Date = Date()) -> Date {
        guard events.count >= total, let oldest = events.first else { return now }
        return oldest.at.addingTimeInterval(window)
    }
}

/// The responder's replay window: a sequence number is accepted once, and only when it
/// is no more than 64 below the highest one seen.
struct SyncReplayWindow {
    private(set) var highest: UInt64 = 0
    /// Bit n set: `highest - 1 - n` was seen.
    private var seen: UInt64 = 0

    func canAccept(_ seq: UInt64) -> Bool {
        guard seq > 0 else { return false }
        if seq > highest { return true }
        let distance = highest - seq
        guard distance >= 1, distance <= 64 else { return false }
        return seen & (1 << (distance - 1)) == 0
    }

    mutating func mark(_ seq: UInt64) {
        guard canAccept(seq) else { return }
        if seq > highest {
            let shift = seq - highest
            seen = shift >= 64 ? 0 : seen << shift
            if highest > 0, shift <= 64 { seen |= 1 << (shift - 1) }
            highest = seq
        } else {
            seen |= 1 << (highest - seq - 1)
        }
    }
}

/// Bounds concurrent work, such as UOA calls, without blocking a thread.
@MainActor
final class SyncAsyncSemaphore {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        available = limit
    }

    func run<T>(_ body: () async throws -> T) async rethrows -> T {
        if available > 0 {
            available -= 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
        defer {
            if waiters.isEmpty { available += 1 } else { waiters.removeFirst().resume() }
        }
        return try await body()
    }
}

/// Wakes long-poll pulls when this store's feed may have new records.
@MainActor
final class SyncChangeSignal {
    private(set) var version = 0
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    func fire() {
        version += 1
        let woken = waiters.values
        waiters.removeAll()
        woken.forEach { $0.resume() }
    }

    /// Returns when `version` moves past `seen`, or at `deadline`.
    func wait(after seen: Int, until deadline: Date) async {
        guard version == seen, deadline > Date() else { return }
        let id = UUID()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters[id] = continuation
            let delay = max(0, deadline.timeIntervalSinceNow)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self?.waiters.removeValue(forKey: id)?.resume()
            }
        }
    }
}
