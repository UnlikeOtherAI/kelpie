import Foundation

/// Finalization has its own grace; active capture must stop at its authored duration.
enum ScriptCaptureDeadline {
    static func allows(elapsed: TimeInterval, maximum: TimeInterval, stopped: Bool) -> Bool {
        stopped || (elapsed.isFinite && elapsed >= 0 && elapsed <= maximum)
    }
}
