import SwiftUI

extension Notification.Name {
    static let showWelcomeCard = Notification.Name("com.kelpie.browser.ios.show-welcome-card")
    static let selectViewportPreset = Notification.Name("com.kelpie.browser.ios.select-viewport-preset")
}

/// Shared orientation lock controlled by the HTTP API.
final class OrientationManager {
    static let shared = OrientationManager()
    var lock: UIInterfaceOrientationMask = .all
}

