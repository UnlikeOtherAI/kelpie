import Foundation

/// Browser preferences and files belong to the browser, independently of host UI state.
enum KelpieStorage {
    private static let bundleID = Bundle.main.bundleIdentifier ?? "kelpie-host"
    static let standalone = ["com.kelpie.browser.macos", "com.unlikeotherai.kelpie"].contains(bundleID)
    static let defaults: UserDefaults = {
        if standalone { return .standard }
        guard let value = UserDefaults(suiteName: bundleID + ".kelpie.browser") else {
            preconditionFailure("Could not create browser preferences")
        }
        return value
    }()

    static func isolated(_ base: URL) -> URL {
        standalone ? base : base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("KelpieBrowser", isDirectory: true)
    }

    static var homeDirectory: URL {
        if standalone { return FileManager.default.homeDirectoryForCurrentUser }
        return isolated(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }

    static var documentsDirectory: URL {
        isolated(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    }
}
