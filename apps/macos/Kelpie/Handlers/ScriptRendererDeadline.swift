import AppKit

/// A caller deadline does not retire native renderer work. Late completions keep the shared lease fenced.
@MainActor
enum ScriptRendererDeadline {
    private final class Retirement: NSObject {
        var pending: [UUID: () -> Void] = [:]
        var waiters: [CheckedContinuation<Void, Never>] = []

        func retire(_ id: UUID) {
            pending.removeValue(forKey: id)?()
            guard pending.isEmpty else { return }
            let current = waiters
            waiters.removeAll()
            for waiter in current { waiter.resume() }
        }
    }

    private final class Attempt<Value> {
        var continuation: CheckedContinuation<Value, Error>?
        var timer: Task<Void, Never>?
        var work: Task<Void, Never>?
        var expired = false
    }

    private static let renderers = NSMapTable<AnyObject, Retirement>.weakToStrongObjects()

    static func isRetiring(_ renderer: any RendererEngine) -> Bool {
        renderers.object(forKey: renderer)?.pending.isEmpty == false
    }

    static func waitForRetirement(_ renderer: any RendererEngine) async {
        guard let retirement = renderers.object(forKey: renderer), !retirement.pending.isEmpty else { return }
        await withCheckedContinuation { retirement.waiters.append($0) }
    }

    static func rendererTerminated(_ renderer: any RendererEngine) {
        guard let retirement = renderers.object(forKey: renderer) else { return }
        for id in Array(retirement.pending.keys) { retirement.retire(id) }
    }

    static func run<Value>(
        renderer: any RendererEngine,
        seconds: UInt64 = 5,
        mutates: Bool = false,
        lease: BrowserControlLease,
        cancelled: @escaping @MainActor () -> Bool = { false },
        operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        guard !isRetiring(renderer) else { throw ScriptWorkflowFailure("BUSY") }
        let retirement = renderers.object(forKey: renderer) ?? Retirement()
        renderers.setObject(retirement, forKey: renderer)
        let attempt = Attempt<Value>()
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            attempt.continuation = continuation
            attempt.timer = Task { @MainActor in
                let deadline = ProcessInfo.processInfo.systemUptime + Double(seconds)
                while !Task.isCancelled {
                    let aborted = cancelled()
                    if aborted || ProcessInfo.processInfo.systemUptime >= deadline {
                        guard let waiting = attempt.continuation else { return }
                        attempt.continuation = nil
                        attempt.expired = true
                        attempt.work?.cancel()
                        lease.retainPending()
                        retirement.pending[id] = { lease.retirePending() }
                        waiting.resume(throwing: ScriptWorkflowFailure(aborted ? "SCRIPT_ABORTED" : "TIMEOUT", mayHaveCompleted: mutates))
                        return
                    }
                    do { try await Task.sleep(nanoseconds: 25_000_000) } catch { return }
                }
            }
            attempt.work = Task { @MainActor in
                let result: Result<Value, Error>
                do { result = .success(try await operation()) } catch { result = .failure(error) }
                attempt.timer?.cancel()
                attempt.timer = nil
                attempt.work = nil
                if attempt.expired { retirement.retire(id) }
                let waiting = attempt.continuation
                attempt.continuation = nil
                waiting?.resume(with: result)
            }
        }
    }
}
