import Foundation

enum FeatureFlags {
    /// 3D DOM Inspector defaults to enabled on mobile so the feature is visible,
    /// but users can still turn it off in Settings.
    static var is3DInspectorEnabled: Bool {
        if let stored = UserDefaults.standard.object(forKey: "enable3DInspector") as? Bool {
            return stored
        }
        if ProcessInfo.processInfo.environment["KELPIE_3D_INSPECTOR"] == "0" {
            return false
        }
        return true
    }
}
