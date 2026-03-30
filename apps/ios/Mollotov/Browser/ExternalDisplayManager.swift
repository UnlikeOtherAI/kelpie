import UIKit
import SwiftUI

// MARK: - Scene delegate (iOS 16+ path)

/// Scene delegate for the Apple TV / external display window scene.
/// Declared in Info.plist under UIWindowSceneSessionRoleExternalDisplayNonInteractive.
class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        print("[ExternalDisplayScene] willConnectTo role=\(session.role.rawValue)")
        guard let windowScene = scene as? UIWindowScene else { return }
        Task { @MainActor in
            ExternalDisplayManager.shared.attachViaScene(windowScene)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        print("[ExternalDisplayScene] sceneDidDisconnect")
        Task { @MainActor in
            ExternalDisplayManager.shared.detach()
        }
    }
}

// MARK: - Manager

/// Manages an external display (Apple TV via AirPlay).
/// Two detection paths: scene-based (iOS 16+) and UIScreen notifications (fallback).
/// Whichever fires first wins; the other is a no-op.
@MainActor
final class ExternalDisplayManager {
    static let shared = ExternalDisplayManager()

    private(set) var isConnected = false
    let externalPort: UInt16 = 8421

    private var serverState: ServerState?
    private var browserState: BrowserState?
    private var externalWindow: UIWindow?

    private init() {}

    /// Start listening for external displays via UIScreen notifications.
    /// Call once from app startup.
    func startMonitoring() {
        NotificationCenter.default.addObserver(
            forName: UIScreen.didConnectNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let screen = notification.object as? UIScreen else { return }
            print("[ExternalDisplay] UIScreen.didConnectNotification: \(screen.bounds.size)")
            Task { @MainActor in self?.attachViaScreen(screen) }
        }
        NotificationCenter.default.addObserver(
            forName: UIScreen.didDisconnectNotification, object: nil, queue: .main
        ) { [weak self] _ in
            print("[ExternalDisplay] UIScreen.didDisconnectNotification")
            Task { @MainActor in self?.detach() }
        }

        // Already connected at launch (e.g. AirPlay was active before app started)
        if UIScreen.screens.count > 1, let screen = UIScreen.screens.last {
            print("[ExternalDisplay] Screen already connected at launch: \(screen.bounds.size)")
            attachViaScreen(screen)
        } else {
            print("[ExternalDisplay] Monitoring started, \(UIScreen.screens.count) screen(s)")
        }
    }

    // MARK: Attach / Detach

    /// Attach via UIWindowScene (called from ExternalDisplaySceneDelegate).
    func attachViaScene(_ windowScene: UIWindowScene) {
        guard !isConnected else {
            print("[ExternalDisplay] Already connected, ignoring scene attach")
            return
        }

        let screen = windowScene.screen
        let (bs, ss) = makeStates(screen: screen)

        let view = ExternalBrowserView(browserState: bs, serverState: ss)
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.backgroundColor = .black

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        finishAttach(bs: bs, ss: ss, window: window, screen: screen)
    }

    /// Attach via UIScreen (called from didConnectNotification).
    private func attachViaScreen(_ screen: UIScreen) {
        guard !isConnected else {
            print("[ExternalDisplay] Already connected, ignoring screen attach")
            return
        }

        let (bs, ss) = makeStates(screen: screen)

        let view = ExternalBrowserView(browserState: bs, serverState: ss)
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.backgroundColor = .black

        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        window.rootViewController = hostingController
        window.isHidden = false
        finishAttach(bs: bs, ss: ss, window: window, screen: screen)
    }

    private func makeStates(screen: UIScreen) -> (BrowserState, ServerState) {
        let info = DeviceInfo.externalDisplay(
            port: Int(externalPort),
            screenSize: screen.bounds.size,
            scale: screen.scale
        )
        let bs = BrowserState()
        let ss = ServerState(deviceInfo: info)
        return (bs, ss)
    }

    private func finishAttach(bs: BrowserState, ss: ServerState, window: UIWindow, screen: UIScreen) {
        browserState = bs
        serverState = ss
        externalWindow = window
        isConnected = true

        ss.startHTTPServer()
        ss.startMDNS()
        print("[ExternalDisplay] Attached \(screen.bounds.size) @ \(screen.scale)x, port \(externalPort)")
    }

    func detach() {
        guard isConnected else { return }
        serverState?.stop()
        externalWindow?.isHidden = true
        externalWindow = nil
        serverState = nil
        browserState = nil
        isConnected = false
        print("[ExternalDisplay] Detached")
    }
}
