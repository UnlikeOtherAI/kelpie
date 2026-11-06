#if DEBUG
import UIKit
import WebKit

/// Bounded, launch-gated facts from existing admission reads only.
@MainActor
enum IOSAdmissionReceipt {
    private static var runID: String?
    private static weak var view: WKWebView?
    private static weak var window: UIWindow?
    private static var document: String?
    private static var started: TimeInterval = 0
    private static var refusedAt: Int?
    private static var first: [Double]?
    private static var last: [Double]?
    private static var firstAt: Int?
    private static var lastAt: Int?
    private static var count = 0
    private static var site: String?
    private static var phase: String?
    private static var identity = true
    private static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--test-paired-admission-receipt")
    }

    static func begin(_ id: String, tab: IOSWorkflowTab) {
        guard enabled else { return }
        runID = id
        view = tab.view
        window = tab.view.window
        document = tab.document
        started = ProcessInfo.processInfo.systemUptime
        refusedAt = nil
        first = nil
        last = nil
        firstAt = nil
        lastAt = nil
        count = 0
        site = nil
        phase = nil
        identity = window != nil
    }

    private static func clearObservations() {
        first = nil
        last = nil
        firstAt = nil
        lastAt = nil
        count = 0
    }

    private static func sameRunAndView(_ id: String, tab: IOSWorkflowTab) -> Bool {
        enabled && runID == id && view === tab.view
    }

    private static func attest(_ tab: IOSWorkflowTab) -> Bool {
        let matches = window != nil && window === tab.view.window && document == tab.document &&
            (try? tab.requireCurrent()) != nil
        identity = identity && matches
        if !identity { clearObservations() }
        return identity
    }

    static func observe(_ id: String, tab: IOSWorkflowTab, phase value: String, values: [CGFloat]) {
        guard sameRunAndView(id, tab: tab), site == nil, count < 1000, attest(tab) else { return }
        if phase != value {
            phase = value
            first = nil
            last = nil
            firstAt = nil
            lastAt = nil
            count = 0
        }
        let numbers = values.map(Double.init)
        guard numbers.allSatisfy({ $0.isFinite && abs($0) <= 100_000 }) else {
            identity = false
            clearObservations()
            return
        }
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        if first == nil {
            first = numbers
            firstAt = elapsed
        }
        last = numbers
        lastAt = elapsed
        count += 1
    }

    static func refuse(_ id: String, tab: IOSWorkflowTab, site value: String) {
        guard sameRunAndView(id, tab: tab), site == nil,
              ["native-layout", "first-scene", "snapshot-changed", "snapshot-deadline"].contains(value) else { return }
        _ = attest(tab)
        site = value
        refusedAt = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        if phase != value {
            first = nil
            last = nil
            firstAt = nil
            lastAt = nil
            count = 0
        }
    }

    static var result: [String: Any] {
        guard enabled, let runID else { return [:] }
        var result: [String: Any] = [
            "runId": runID,
            "identityValid": identity,
            "count": count
        ]
        if let refusedAt { result["elapsedMs"] = refusedAt }
        if let site { result["site"] = site }
        if let first { result["first"] = first }
        if let last { result["last"] = last }
        if let firstAt { result["firstAtMs"] = firstAt }
        if let lastAt { result["lastAtMs"] = lastAt }
        return result
    }
}
#endif
