import Foundation

/// An existing load must retire before reserving the next mutation's navigation token.
@MainActor
enum IOSWorkflowNavigation {
    /// Once a load is issued, an acknowledged Stop leaves its navigation outcome uncertain.
    static func interruption(_ error: Error) -> IOSWorkflowFailure {
        let code = (error as? IOSWorkflowFailure)?.code == "SCRIPT_ABORTED" ? "SCRIPT_ABORTED" : "NAVIGATION_INTERRUPTED"
        return IOSWorkflowFailure(code, mayHaveCompleted: true)
    }

    static func issue(
        on view: AnyObject,
        deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(10)),
        authorize: () async throws -> Void,
        isLoading: () -> Bool = { false },
        load: () -> AnyObject?
    ) async throws -> ConnectNavigationLease {
        while true {
            guard !Task.isCancelled else { throw IOSWorkflowFailure("SCRIPT_ABORTED") }
            try await authorize()
            guard !Task.isCancelled else { throw IOSWorkflowFailure("SCRIPT_ABORTED") }
            guard ContinuousClock.now < deadline else { throw IOSWorkflowFailure("NAVIGATION_BUSY") }
            if !isLoading() { break }
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { throw IOSWorkflowFailure("SCRIPT_ABORTED") }
        }
        // No suspension between the final authorized state check and the pinned load.
        let lease = ConnectNavigationLease(initial: ConnectDocument.version(view))
        ConnectDocument.reserve(view, lease: lease)
        guard let navigation = load() else {
            ConnectDocument.reserve(view, lease: nil)
            throw IOSWorkflowFailure("NAVIGATION_FAILED")
        }
        ConnectDocument.issued(view, navigation: navigation)
        return lease
    }
}
