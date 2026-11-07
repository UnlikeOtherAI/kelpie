import Foundation

/// Browser preferences and files belong to the browser, independently of host UI state.
enum KelpieStorage {
    private static let bundleID = Bundle.main.bundleIdentifier ?? "kelpie-host"
    static let standalone = ["com.kelpie.browser.macos", "com.unlikeotherai.kelpie"].contains(bundleID)
    static let defaults = standalone ? KelpieStorage.defaults : UserDefaults(suiteName: bundleID + ".kelpie.browser")!

    static func isolated(_ base: URL) -> URL {
        standalone ? base : base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("KelpieBrowser", isDirectory: true)
    }

    static var homeDirectory: URL { isolated(KelpieStorage.homeDirectory) }
    static var documentsDirectory: URL {
        isolated(KelpieStorage.documentsDirectory)
    }
}
