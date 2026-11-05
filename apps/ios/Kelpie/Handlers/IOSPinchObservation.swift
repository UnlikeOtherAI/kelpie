#if DEBUG
import UIKit
import WebKit

/// Bounded, read-only diagnostics for one owned native pinch recognizer.
@MainActor
final class IOSPinchObservation: NSObject {
    private static var active: IOSPinchObservation?
    private weak var view: WKWebView?
    private weak var window: UIWindow?
    private weak var recognizer: UIPinchGestureRecognizer?
    private var expiry: Task<Void, Never>?
    private var began = 0
    private var changed = 0
    private var ended = 0
    private var cancelled = 0
    private var maximumScale: CGFloat = 0

    private init(view: WKWebView, recognizer: UIPinchGestureRecognizer, window: UIWindow) {
        self.view = view
        self.recognizer = recognizer
        self.window = window
        super.init()
        recognizer.addTarget(self, action: #selector(observe(_:)))
    }

    static func sample(view: WKWebView) -> [String: Any] {
        if let active {
            let sameView = active.view === view && active.window != nil && active.window === view.window &&
                active.recognizer === view.scrollView.pinchGestureRecognizer
            let result = active.facts(sameView: sameView)
            active.retire()
            return result
        }
        guard let recognizer = view.scrollView.pinchGestureRecognizer, let window = view.window else {
            return ["armed": false]
        }
        let probe = IOSPinchObservation(view: view, recognizer: recognizer, window: window)
        active = probe
        probe.expiry = Task { @MainActor [weak probe] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            probe?.retire()
        }
        return ["armed": true]
    }

    @objc private func observe(_ sender: UIPinchGestureRecognizer) {
        guard sender === recognizer, let view, window != nil, view.window === window else { retire(); return }
        switch sender.state {
        case .began: began += 1
        case .changed: changed += 1
        case .ended: ended += 1
        case .cancelled, .failed: cancelled += 1
        default: break
        }
        if sender.scale.isFinite { maximumScale = max(maximumScale, min(sender.scale, 100)) }
    }

    private func facts(sameView: Bool) -> [String: Any] {
        ["armed": false, "sameView": sameView, "began": began, "changed": changed,
         "ended": ended, "cancelled": cancelled, "maximumScale": maximumScale]
    }

    private func retire() {
        recognizer?.removeTarget(self, action: #selector(observe(_:)))
        expiry?.cancel()
        expiry = nil
        if Self.active === self { Self.active = nil }
    }
}
#endif
