import Foundation

@main
struct ScriptDeadlineAcceptance {
    static func main() {
        precondition(ScriptCaptureDeadline.allows(elapsed: 0, maximum: 0.1, stopped: false))
        precondition(ScriptCaptureDeadline.allows(elapsed: 0.1, maximum: 0.1, stopped: false))
        precondition(!ScriptCaptureDeadline.allows(elapsed: 0.100001, maximum: 0.1, stopped: false))
        precondition(!ScriptCaptureDeadline.allows(elapsed: 60.001, maximum: 60, stopped: false))
        precondition(ScriptCaptureDeadline.allows(elapsed: 61, maximum: 60, stopped: true))
        precondition(!ScriptCaptureDeadline.allows(elapsed: .nan, maximum: 60, stopped: false))
        precondition(!ScriptCaptureDeadline.allows(elapsed: .infinity, maximum: 60, stopped: false))
        precondition(!ScriptCaptureDeadline.allows(elapsed: -1, maximum: 60, stopped: false))
        let already = ScriptCaptureFinalization(started: 100, alreadyAborted: true)
        precondition(already.allows(now: 100, isAborted: true))
        precondition(already.allows(now: 101.999, isAborted: true))
        precondition(!already.allows(now: 102, isAborted: true))
        let active = ScriptCaptureFinalization(started: 100, alreadyAborted: false)
        precondition(active.allows(now: 144.999, isAborted: false))
        precondition(!active.allows(now: 145, isAborted: false))
        precondition(!active.allows(now: 100, isAborted: true))
        print("PASS active deadline boundary, finite elapsed and separate finalization grace")
    }
}
