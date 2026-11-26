import AppKit
import Darwin

@main
@MainActor
enum KelpieLauncher {
    static func main() {
        do {
            let instance = try StandaloneInstance()
            #if !KELPIE_WEBKIT_ONLY
            migrateDirectPreferences()
            #endif
            withExtendedLifetime(instance) { KelpieApp.main() }
        } catch {
            if let error = error as? POSIXError, error.code == .EADDRINUSE {
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.unlikeotherai.kelpie")
                    .first { $0.processIdentifier != getpid() }?.activate(options: [])
                fputs("Kelpie is already running on this computer\n", stderr)
            } else {
                fputs("Cannot acquire Kelpie application ownership: \(error.localizedDescription)\n", stderr)
            }
            exit(EXIT_FAILURE)
        }
    }

    #if !KELPIE_WEBKIT_ONLY
    private static func migrateDirectPreferences() {
        let defaults = UserDefaults.standard
        let marker = "kelpie.didImportDirectPreferences"
        guard !defaults.bool(forKey: marker) else { return }
        let previous = defaults.persistentDomain(forName: "com.kelpie.browser.macos") ?? [:]
        let keys = [
            "sessionTabs", "sessionTabURLs", "sessionActiveIndex", "homeURL", "hideWelcomeCard", "enable3DInspector",
            "kelpie_bookmarks", "kelpie_bookmarks_tree_v1", "kelpie_history", "com.kelpie.partition-map",
            "com.kelpie.renderer-engine", "com.kelpie.viewport-mode", "com.kelpie.viewport-scale",
            "com.kelpie.viewport-orientation", "com.kelpie.macos.ai-panel-open", "com.kelpie.macos.ai-panel-width",
            "com.kelpie.macos.shell-window-width", "com.kelpie.macos.shell-window-height",
            "com.kelpie.macos.shell-window-origin-set", "com.kelpie.macos.shell-window-origin-x",
            "com.kelpie.macos.shell-window-origin-y", "com.kelpie.device-id", "nessie.connect.installation",
            // The direct build keeps its encrypted settings file in the same Application Support directory.
            "secretstore.key.v1", "kelpie_uoa_public_client_id", "ai.openaiEndpoints.v1"
        ]
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = previous[key] { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: marker)
    }
    #endif
}
