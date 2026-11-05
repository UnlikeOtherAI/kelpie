import UIKit

#if DEBUG
/// Bounded test-only facts for the current edit. It never changes keyboard or viewport state.
@MainActor
final class IOSKeyboardGeometryProbe {
    private let tab: IOSWorkflowTab
    private let document: String
    private weak var window: UIWindow?
    private var tokens: [NSObjectProtocol] = []

    init?(tab: IOSWorkflowTab) {
        guard ProcessInfo.processInfo.arguments.contains("--test-keyboard-geometry"), let window = tab.view.window else { return nil }
        self.tab = tab
        self.window = window
        self.document = tab.document
        for (name, phase) in [(UIResponder.keyboardWillChangeFrameNotification, "will"),
                              (UIResponder.keyboardDidChangeFrameNotification, "did")] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.record(note, phase: phase) }
            })
        }
    }

    func stop() {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens.removeAll()
    }

    private func record(_ note: Notification, phase: String) {
        guard let window, let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let local = (note.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber)?.boolValue == true
        let inWindow = window.convert(end, from: window.screen.coordinateSpace)
        let inView = tab.view.convert(inWindow, from: window)
        let overlap = tab.view.bounds.intersection(inView)
        let guide = window.keyboardLayoutGuide.layoutFrame
        let sameTab = (try? tab.requireCurrent()) != nil
        let values: [CGFloat] = [
            local ? 1 : 0, sameTab ? 1 : 0, tab.document == document ? 1 : 0,
            tab.view.window === window ? 1 : 0, window.windowScene?.activationState == .foregroundActive ? 1 : 0,
            tab.rendererContainsFirstResponder ? 1 : 0,
            tab.view.bounds.width, tab.view.bounds.height, end.minX, end.minY, end.width, end.height,
            overlap.isNull ? 0 : overlap.minX, overlap.isNull ? 0 : overlap.minY,
            overlap.isNull ? 0 : overlap.width, overlap.isNull ? 0 : overlap.height,
            guide.minX, guide.minY, guide.width, guide.height
        ]
        guard values.allSatisfy({ $0.isFinite && abs($0) <= 10000 }) else { return }
        let encoded = values.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double($0)) }
        print("[WorkflowKeyboardGeometry] phase=" + phase + " values=" + encoded.joined(separator: ","))
    }
}
#endif
