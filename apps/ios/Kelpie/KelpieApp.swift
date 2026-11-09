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
    @StateObject private var browser = KelpieBrowserSession(externalDisplaysEnabled: true)
    @StateObject private var updates = AppUpdates()

    init() { AppRevealSetup.configure() }

    var body: some Scene {
        WindowGroup {
            KelpieBrowserView(session: browser).modifier(AppUpdatePresentation(updates: updates))
        }
            .commands { KelpieBrowserCommands() }
    }
}
