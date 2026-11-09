import AppKit

/// Keeps the start page's site screenshots current.
///
/// Mirrors `SitePreviewCapture` in the desktop engine: once a page has
/// finished loading and stayed put for a moment, the active tab's viewport is
/// snapshotted and handed to `SitePreviewCache`. Only ordinary web pages in
/// persistent storage are captured, and a host at most every two minutes
/// while browsing around it.
@MainActor
final class SitePreviewCapturer {
    static let shared = SitePreviewCapturer()

    private static let settle: Duration = .milliseconds(1500)
    private static let refresh: TimeInterval = 120

    private var pending: [UUID: Task<Void, Never>] = [:]
    private var capturedAt: [String: Date] = [:]

    /// Called on every navigation state change of `tab`.
    func tabChanged(_ tab: Tab, isActive: @escaping @MainActor () -> Bool) {
        pending[tab.id]?.cancel()
        pending[tab.id] = nil
        guard !tab.isLoading, !tab.isStartPage, tab.persistent,
              let url = URL(string: tab.currentURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), !host.isEmpty else { return }
        let expected = tab.currentURL
        pending[tab.id] = Task { [weak self, weak tab] in
            try? await Task.sleep(for: Self.settle)
            guard let self, let tab, !Task.isCancelled, isActive(), !tab.isLoading,
                  tab.currentURL == expected, self.isDue(host) else { return }
            guard let snapshot = try? await tab.renderer.takeSnapshot(),
                  !Task.isCancelled, tab.currentURL == expected else { return }
            SitePreviewCache.shared.store(snapshot, forHost: host)
            self.capturedAt[host] = Date()
        }
    }

    func tabClosed(_ id: UUID) {
        pending[id]?.cancel()
        pending[id] = nil
    }

    /// Clearing history resets the throttle along with the screenshots.
    func historyCleared() {
        capturedAt.removeAll()
    }

    private func isDue(_ host: String) -> Bool {
        guard let last = capturedAt[host], SitePreviewCache.shared.image(forHost: host) != nil else { return true }
        return Date().timeIntervalSince(last) >= Self.refresh
    }
}
