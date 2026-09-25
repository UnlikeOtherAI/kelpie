import AuthenticationServices
#if os(macOS)
import AppKit
typealias UOAAvatar = NSImage
#else
import UIKit
typealias UOAAvatar = UIImage
#endif

/// Platform presentation adapter; the account state machine and transport are shared.
@MainActor
enum UOAPresentation {
    static var clientName: String {
        #if os(macOS)
        "Kelpie for Mac"
        #else
        "Kelpie for iOS"
        #endif
    }

    static var anchor: ASPresentationAnchor {
        #if os(macOS)
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #else
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        #endif
    }
}
