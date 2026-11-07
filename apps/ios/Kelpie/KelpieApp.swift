import SwiftUI
import KelpieBrowser

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        KelpieBrowserSession.supportedOrientations
    }
}

@main
struct KelpieApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var browser = KelpieBrowserSession()

    var body: some Scene {
        WindowGroup { KelpieBrowserView(session: browser) }
            .commands { KelpieBrowserCommands() }
    }
}
