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
        print("PASS active deadline boundary, finite elapsed and separate finalization grace")
    }
}
