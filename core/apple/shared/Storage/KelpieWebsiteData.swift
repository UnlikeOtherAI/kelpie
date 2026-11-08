import Foundation
import WebKit

/// Embedded browser cookies and page storage never join the host WebView's profile.
@MainActor
enum KelpieWebsiteData {
    private static let instance = KelpieProfileValue<WKWebsiteDataStore>()
    static var store: WKWebsiteDataStore { instance.get {
        if KelpieStorage.standalone { return .default() }
        if #available(iOS 17.0, macOS 14.0, *) {
            let key = "kelpie.browser.website-store"
            let identifier: UUID
            if let value = KelpieStorage.defaults.string(forKey: key), let existing = UUID(uuidString: value) {
                identifier = existing
            } else {
                identifier = UUID()
                KelpieStorage.defaults.set(identifier.uuidString, forKey: key)
            }
            return WKWebsiteDataStore(forIdentifier: identifier)
        }
        // iOS 16 cannot persist a second isolated WebKit profile.
        return .nonPersistent()
    } }
}
