import Foundation
#if os(macOS)
import AppKit
typealias UOAAvatar = NSImage
#else
import UIKit
typealias UOAAvatar = UIImage
#endif

/// Presents the in-app login surface for `url` and reports how it ended. Returns nil when it cannot be shown.
typealias UOALoginPresenter = @MainActor (_ url: URL, _ finish: @escaping (UOALoginResult) -> Void) -> UOALoginSurface?

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

    /// Shows the login in an in-app web view on the browser tabs' website data store, so the
    /// identity-provider session it creates (Google's included) is shared with every tab.
    static func presentLogin(_ url: URL, finish: @escaping (UOALoginResult) -> Void) -> UOALoginSurface? {
        #if os(macOS)
        UOALoginWindowController.present(url, finish: finish)
        #else
        UOALoginViewController.present(url, finish: finish)
        #endif
    }
}
