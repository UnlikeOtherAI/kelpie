import Foundation

enum FeatureFlags {
    /// 3D DOM Inspector — experimental, behind feature flag.
    /// Enable via Settings toggle or `KELPIE_3D_INSPECTOR=1` environment variable.
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
