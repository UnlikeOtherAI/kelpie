import AppKit
import Darwin

@main
@MainActor
enum KelpieLauncher {
    static func main() {
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("com.kelpie.browser.macos", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let instance = try StandaloneInstance(lockURL: directory.appendingPathComponent("standalone.lock"))
            withExtendedLifetime(instance) { KelpieApp.main() }
        } catch {
            if let error = error as? POSIXError, error.code == .EAGAIN {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.kelpie.browser.macos")
                    .first { $0.processIdentifier != getpid() }?.activate(options: [])
                fputs("Kelpie is already running on this computer\n", stderr)
            } else {
                fputs("Cannot acquire Kelpie application ownership: \(error.localizedDescription)\n", stderr)
            }
            exit(EXIT_FAILURE)
        }
    }
}
