import WebKit

/// WebKit callbacks can outlive a caller's deadline. Keep a timed-out renderer fenced until its callback retires.
@MainActor
enum IOSRendererDeadline {
    @MainActor
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

    @MainActor
    private final class Attempt<Value> {
        var continuation: CheckedContinuation<Value, Error>?
        var timeout: Task<Void, Never>?
        var expired = false
        var work: Task<Void, Never>?
    }

    private static let views = NSMapTable<WKWebView, Retirement>.weakToStrongObjects()

    static func isRetiring(_ view: WKWebView) -> Bool {
        views.object(forKey: view)?.pending.isEmpty == false
    }

    static func waitForRetirement(_ view: WKWebView) async {
        guard let retirement = views.object(forKey: view), !retirement.pending.isEmpty else { return }
        await withCheckedContinuation { retirement.waiters.append($0) }
    }

    static func rendererTerminated(_ view: WKWebView) {
        guard let retirement = views.object(forKey: view) else { return }
        for id in Array(retirement.pending.keys) { retirement.retire(id) }
    }

    static func run<Value>(
        view: WKWebView,
        seconds: UInt64 = 5,
        mutates: Bool = false,
        lease: BrowserControlLease? = nil,
        operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        guard !isRetiring(view) else { throw IOSWorkflowFailure("BUSY") }
        let retirement = views.object(forKey: view) ?? Retirement()
        views.setObject(retirement, forKey: view)
        let attempt = Attempt<Value>()
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            attempt.continuation = continuation
            attempt.timeout = Task { @MainActor in
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                guard !Task.isCancelled, let waiting = attempt.continuation else { return }
                attempt.continuation = nil
                attempt.expired = true
                attempt.work?.cancel()
                lease?.retainPending()
                retirement.pending[id] = { lease?.retirePending() }
                waiting.resume(throwing: IOSWorkflowFailure("TIMEOUT", mayHaveCompleted: mutates))
            }
            attempt.work = Task { @MainActor in
                let result: Result<Value, Error>
                do { result = .success(try await operation()) } catch { result = .failure(error) }
                attempt.timeout?.cancel()
                attempt.timeout = nil
                attempt.work = nil
                if attempt.expired { retirement.retire(id) }
                let waiting = attempt.continuation
                attempt.continuation = nil
                waiting?.resume(with: result)
            }
        }
    }
}
