#if DEBUG
import UIKit
import WebKit

/// Bounded, read-only diagnostics for one owned native pinch recognizer.
@MainActor
final class IOSPinchObservation: NSObject {
    private static var active: IOSPinchObservation?
    private static var retiredReason: String?
    private weak var view: WKWebView?
    private weak var window: UIWindow?
    private weak var recognizer: UIPinchGestureRecognizer?
    private let document: String
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
        self.document = ConnectDocument.version(view)
        super.init()
        recognizer.addTarget(self, action: #selector(observe(_:)))
    }

    static func sample(view: WKWebView) -> [String: Any] {
        if let active {
            let sameView = active.view === view && active.window != nil && active.window === view.window &&
                active.recognizer === view.scrollView.pinchGestureRecognizer
            let sameDocument = sameView && active.document == ConnectDocument.version(view)
            let result = active.facts(sameView: sameView, sameDocument: sameDocument)
            active.retire()
            return result
        }
        if let reason = retiredReason {
            retiredReason = nil
            return ["armed": false, "retiredReason": reason]
        }
        guard let recognizer = view.scrollView.pinchGestureRecognizer, let window = view.window else {
            return ["armed": false]
        }
        let probe = IOSPinchObservation(view: view, recognizer: recognizer, window: window)
        active = probe
        probe.expiry = Task { @MainActor [weak probe] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            probe?.retire(reason: "expired")
        }
        return ["armed": true]
    }

    @objc private func observe(_ sender: UIPinchGestureRecognizer) {
        guard sender === recognizer, let view, window != nil, view.window === window,
              document == ConnectDocument.version(view) else { retire(reason: "identity"); return }
        switch sender.state {
        case .began: began = min(began + 1, 10000)
        case .changed: changed = min(changed + 1, 10000)
        case .ended: ended = min(ended + 1, 10000)
        case .cancelled, .failed: cancelled = min(cancelled + 1, 10000)
        default: break
        }
        if sender.scale.isFinite { maximumScale = max(maximumScale, min(sender.scale, 100)) }
    }

    private func facts(sameView: Bool, sameDocument: Bool) -> [String: Any] {
        ["armed": false, "sameView": sameView, "sameDocument": sameDocument, "began": began, "changed": changed,
         "ended": ended, "cancelled": cancelled, "maximumScale": maximumScale]
    }

    private func retire(reason: String? = nil) {
        recognizer?.removeTarget(self, action: #selector(observe(_:)))
        expiry?.cancel()
        expiry = nil
        if Self.active === self {
            Self.active = nil
            Self.retiredReason = reason
        }
    }
}
#endif
