import Foundation

/// Reserve only after asynchronous authorization, then issue and record on the same pinned view.
@MainActor
enum IOSWorkflowNavigation {
    static func issue(
        on view: AnyObject,
        authorize: () async throws -> Void,
        load: () -> AnyObject?
    ) async throws -> ConnectNavigationLease {
        try await authorize()
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
