import AppKit
import Darwin

@main
@MainActor
enum KelpieLauncher {
    static func main() {
        do {
            let instance = try StandaloneInstance()
            withExtendedLifetime(instance) { KelpieApp.main() }
        } catch {
            if let error = error as? POSIXError, error.code == .EADDRINUSE {
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
