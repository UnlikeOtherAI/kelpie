import Foundation

/// Native navigation callbacks invalidate the document even on same-URL reloads.
@MainActor
enum ConnectDocument {
    private static let versions = NSMapTable<AnyObject, NSString>.weakToStrongObjects()
    private static let leases = NSMapTable<AnyObject, ConnectNavigationLease>.weakToStrongObjects()

    static func version(_ view: AnyObject) -> String {
        if let value = versions.object(forKey: view) { return value as String }
        let value = UUID().uuidString
        versions.setObject(value as NSString, forKey: view)
        return value
    }

    static func reserve(_ view: AnyObject, lease: ConnectNavigationLease?) {
        if let lease { leases.setObject(lease, forKey: view) } else { leases.removeObject(forKey: view) }
    }

    static func issued(_ view: AnyObject, navigation: AnyObject?) {
        leases.object(forKey: view)?.issued(navigation)
    }

    static func navigated(_ view: AnyObject, navigation: AnyObject? = nil) {
        let previous = version(view)
        let current = UUID().uuidString
        versions.setObject(current as NSString, forKey: view)
        leases.object(forKey: view)?.started(previous: previous, version: current, navigation: navigation)
    }
}
