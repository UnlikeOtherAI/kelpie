import SwiftUI

/// Shared orientation lock controlled by the HTTP API.
final class OrientationManager {
    static let shared = OrientationManager()
    var lock: UIInterfaceOrientationMask = .all
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationManager.shared.lock
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        print("[AppDelegate] configurationForConnecting role=\(connectingSceneSession.role.rawValue)")
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            print("[AppDelegate] Creating external display configuration")
            let config = UISceneConfiguration(
                name: "External Display",
                sessionRole: connectingSceneSession.role
            )
            config.delegateClass = ExternalDisplaySceneDelegate.self
            return config
        }
        return UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }
}

@main
struct MollotovApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var browserState = BrowserState()
    @StateObject private var serverState = ServerState()

    var body: some Scene {
        WindowGroup {
            BrowserView(browserState: browserState, serverState: serverState)
                .onAppear { startServices() }
        }
    }

    private func startServices() {
        serverState.startHTTPServer()
        serverState.startMDNS()
        ExternalDisplayManager.shared.startMonitoring()
        #if DEBUG
        AppRevealSetup.configure()
        #endif
    }
}
