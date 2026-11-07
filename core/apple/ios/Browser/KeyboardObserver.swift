import UIKit

/// Tracks keyboard visibility and height via UIResponder notifications.
@MainActor
final class KeyboardObserver {

    private(set) var isVisible = false
    private(set) var height: CGFloat = 0

    private var showToken: NSObjectProtocol?
    private var hideToken: NSObjectProtocol?

    init() {
        let center = NotificationCenter.default
        showToken = center.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleShow(notification)
            }
        }
        hideToken = center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleHide(notification)
            }
        }
    }

    deinit {
        if let showToken { NotificationCenter.default.removeObserver(showToken) }
        if let hideToken { NotificationCenter.default.removeObserver(hideToken) }
    }

    /// Current screen bounds (points).
    var screenBounds: CGRect {
        UIScreen.main.bounds
    }

    /// Viewport height accounting for keyboard overlap.
    var visibleViewportHeight: CGFloat {
        screenBounds.height - (isVisible ? height : 0)
    }

    // MARK: - Private

    private func handleShow(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        // Floating keyboards on iPad don't anchor to the bottom edge and don't reduce the viewport.
        guard frame.maxY >= UIScreen.main.bounds.height - 1 else { return }
        isVisible = true
        height = frame.height
    }

    private func handleHide(_ notification: Notification) {
        isVisible = false
        height = 0
    }
}
