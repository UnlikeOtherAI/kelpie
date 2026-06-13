import Foundation
import SwiftUI

/// Observable bridge between the headless `PairingStore` and SwiftUI. The
/// HTTPServer pokes this coordinator after creating a pending request; the
/// SwiftUI hierarchy observes `currentPrompt` to show a modal.
@MainActor
final class PairApprovalCoordinator: ObservableObject {
    @Published private(set) var currentPrompt: PairingStore.PendingRequest?
    /// Last decision the user took, used by the prompt sheet to dismiss itself.
    @Published private(set) var lastResolvedRequestId: String?

    let store: PairingStore

    init(store: PairingStore) {
        self.store = store
    }

    /// Called when a new pair request arrives; recomputes the visible prompt.
    func refresh() {
        let next = store.visiblePending().first
        currentPrompt = next
    }

    func approve(requestId: String, persist: Bool) {
        _ = store.approve(requestId: requestId, persist: persist)
        lastResolvedRequestId = requestId
        refresh()
    }

    func deny(requestId: String) {
        store.deny(requestId: requestId)
        lastResolvedRequestId = requestId
        refresh()
    }
}
