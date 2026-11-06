#if DEBUG
import UIKit
import WebKit

/// One test-only receipt, bound to the owned run, view, window and document.
@MainActor
final class IOSImmersiveLayoutTrace {
    private static var active: IOSImmersiveLayoutTrace?
    private let runID: String
    private weak var tab: IOSWorkflowTab?
    private weak var view: WKWebView?
    private weak var window: UIWindow?
    private let document: String
    private var receipt: [String: Any]

    private init(runID: String, tab: IOSWorkflowTab, window: UIWindow) {
        self.runID = runID
        self.tab = tab
        self.view = tab.view
        self.window = window
        self.document = tab.document
        self.receipt = ["runId": runID, "request": Self.raw(tab.view)]
    }

    static func begin(runID: String, tab: IOSWorkflowTab, immersive: Bool) {
        guard ProcessInfo.processInfo.arguments.contains("--test-paired-geometry-receipt"),
              immersive, let window = tab.view.window else { active = nil; return }
        active = IOSImmersiveLayoutTrace(runID: runID, tab: tab, window: window)
    }

    static func applied(view: WKWebView, immersive: Bool, clearance: CGFloat, range: ClosedRange<CGFloat>) {
        guard let trace = active, trace.valid(view), immersive, clearance == 0,
              range.lowerBound == 0, range.upperBound == 0, trace.receipt["application"] == nil else { return }
        trace.receipt["application"] = raw(view)
    }

    static func baseline(runID: String, tab: IOSWorkflowTab, viewport: IOSWorkflowTab.Viewport) {
        guard let trace = active, trace.runID == runID, trace.valid(tab.view),
              trace.receipt["baseline"] == nil else { return }
        var facts = raw(tab.view)
        facts["css"] = [Double(viewport.layout.width), Double(viewport.layout.height),
                        Double(viewport.visible.width), Double(viewport.visible.height),
                        Double(viewport.scale), Double(viewport.pixelRatio)]
        trace.receipt["baseline"] = facts
    }

    static var evidence: [String: Any] {
        guard let trace = active else { return [:] }
        var result = trace.receipt
        result["identityValid"] = trace.view.map(trace.valid) ?? false
        return result
    }

    private func valid(_ candidate: WKWebView) -> Bool {
        view === candidate && window != nil && candidate.window === window &&
            tab?.view === candidate && tab?.document == document
    }

    private static func raw(_ view: WKWebView) -> [String: Any] {
        func rect(_ value: CGRect) -> [Double] {
            [value.minX, value.minY, value.width, value.height].map(Double.init)
        }
        func inset(_ value: UIEdgeInsets) -> [Double] {
            [value.top, value.left, value.bottom, value.right].map(Double.init)
        }
        let frame = view.window.map { view.convert(view.bounds, to: $0) } ?? .null
        let fields = [rect(view.bounds), rect(frame), inset(view.safeAreaInsets),
                      inset(view.scrollView.adjustedContentInset), inset(view.scrollView.contentInset),
                      inset(view.minimumViewportInset), inset(view.maximumViewportInset)]
        guard fields.flatMap({ $0 }).allSatisfy({ $0.isFinite && abs($0) <= 100_000 }) else { return [:] }
        var facts: [String: Any] = [
            "bounds": fields[0], "windowFrame": fields[1], "safe": fields[2], "adjusted": fields[3],
            "scrollContent": fields[4], "minimumViewport": fields[5], "maximumViewport": fields[6],
            "obscuredAvailable": false
        ]
        if #available(iOS 26.0, *) {
            let obscured = inset(view.obscuredContentInsets)
            guard obscured.allSatisfy({ $0.isFinite && abs($0) <= 100_000 }) else { return [:] }
            facts["obscuredAvailable"] = true
            facts["obscuredContent"] = obscured
        }
        return facts
    }
}
#endif
