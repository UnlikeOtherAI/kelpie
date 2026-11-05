import Foundation

/// Finalization has its own grace; active capture must stop at its authored duration.
enum ScriptCaptureDeadline {
    static func allows(elapsed: TimeInterval, maximum: TimeInterval, stopped: Bool) -> Bool {
        stopped || (elapsed.isFinite && elapsed >= 0 && elapsed <= maximum)
    }
}

struct ScriptCaptureFinalization: Sendable {
    let alreadyAborted: Bool
    let deadline: TimeInterval

    init(started: TimeInterval, alreadyAborted: Bool) {
        self.alreadyAborted = alreadyAborted
        deadline = started + (alreadyAborted ? 2 : 45)
    }

    func allows(now: TimeInterval, isAborted: Bool) -> Bool {
        now < deadline && (alreadyAborted || !isAborted)
    }
}
