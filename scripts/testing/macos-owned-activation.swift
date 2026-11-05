import AppKit
import Foundation

// Hosted-only helper: validate the exact candidate PID and executable before any activation.
let args = CommandLine.arguments
guard args.count == 4, ["activate", "check"].contains(args[1]),
      let pid = Int32(args[2]), pid > 1,
      let candidate = NSRunningApplication(processIdentifier: pid),
      let actual = candidate.executableURL?.standardizedFileURL.resolvingSymlinksInPath(),
      actual.path == URL(fileURLWithPath: args[3]).standardizedFileURL.resolvingSymlinksInPath().path else {
    fputs("OWNED_ACTIVATION_IDENTITY\n", stderr)
    exit(1)
}
if args[1] == "activate" {
    guard candidate.activate(options: []) else {
        fputs("OWNED_ACTIVATION_REJECTED\n", stderr)
        exit(1)
    }
}
let end = Date().addingTimeInterval(5)
while !candidate.isActive && Date() < end {
    RunLoop.current.run(until: Date().addingTimeInterval(0.025))
}
guard candidate.isActive, !candidate.isTerminated else {
    fputs("OWNED_ACTIVATION_INACTIVE\n", stderr)
    exit(1)
}
print("active")
