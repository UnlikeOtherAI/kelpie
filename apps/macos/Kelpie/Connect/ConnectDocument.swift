import Foundation

/// Native navigation callbacks invalidate the document even on same-URL reloads.
@MainActor
enum ConnectDocument {
    private static let versions = NSMapTable<AnyObject, NSString>.weakToStrongObjects()

    static func version(_ view: AnyObject) -> String {
        if let value = versions.object(forKey: view) { return value as String }
        let value = UUID().uuidString
        versions.setObject(value as NSString, forKey: view)
        return value
    }

    static func navigated(_ view: AnyObject) {
        versions.setObject(UUID().uuidString as NSString, forKey: view)
    }
}
