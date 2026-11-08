import Foundation

/// Browser preferences and files belong to the browser, independently of host UI state.
enum KelpieStorage {
    private static let bundleID = Bundle.main.bundleIdentifier ?? "kelpie-host"
    static let standalone = ["com.kelpie.browser.macos", "com.unlikeotherai.kelpie"].contains(bundleID)
    private static let lock = NSLock()
    private static var selectedProfile = "default"
    private static let values = KelpieProfileValue<UserDefaults>()

    static var profileID: String {
        lock.lock()
        defer { lock.unlock() }
        return selectedProfile
    }

    static func select(profile: String) {
        lock.lock()
        selectedProfile = profile
        lock.unlock()
    }

    static var defaults: UserDefaults { values.get {
        if standalone { return .standard }
        guard let value = UserDefaults(suiteName: bundleID + ".kelpie.browser." + profileID) else {
            preconditionFailure("Could not create browser preferences")
        }
        return value
    } }

    static func isolated(_ base: URL) -> URL {
        standalone ? base : base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("KelpieBrowser", isDirectory: true)
            .appendingPathComponent(profileID, isDirectory: true)
    }

    static var homeDirectory: URL {
        if standalone { return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true) }
        return isolated(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }

    static var documentsDirectory: URL {
        isolated(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    }
}
