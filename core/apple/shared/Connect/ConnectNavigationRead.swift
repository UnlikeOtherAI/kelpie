import Foundation

@MainActor
extension HandlerContext {
    /// Completion metadata has a separate authority from the original document's mutation guard.
    func waitForNavigationRead() async throws {
        for _ in 0..<100 {
            try Task.checkCancellation()
            if remoteNavigationReadGuard?() != false { return }
            guard remoteNavigationWaitGuard?() == true else { throw CancellationError() }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ConnectBrowser.Failure("Navigation did not settle before its completion deadline")
    }
}
