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

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationManager.shared.lock
    }

}

@main
struct KelpieApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var browserState: BrowserState
    @StateObject private var serverState: ServerState
    @StateObject private var tabStore: TabStore
    @AppStorage(ipadMobileStagePresetDefaultsKey) private var iPadMobileStagePresetID = ""
    private let environment = ProcessInfo.processInfo.environment

    init() {
        let bs = BrowserState()
        let ss = ServerState()
        let ts = TabStore(handlerContext: ss.handlerContext)
        ss.tabStore = ts
        _browserState = StateObject(wrappedValue: bs)
        _serverState = StateObject(wrappedValue: ss)
        _tabStore = StateObject(wrappedValue: ts)
    }

    var body: some Scene {
        WindowGroup {
            BrowserView(browserState: browserState, serverState: serverState, tabStore: tabStore)
                .onAppear { startServices() }
                .onChange(of: scenePhase) { phase in
                    handleScenePhase(phase)
                }
        }
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Show Welcome Screen") {
                    NotificationCenter.default.post(name: .showWelcomeCard, object: nil)
                }

                Divider()

                Button("Open Kelpie Website") {
                    openHelpURL("https://unlikeotherai.github.io/kelpie")
                }

                Button("Open GitHub Repository") {
                    openHelpURL("https://github.com/UnlikeOtherAI/kelpie")
                }

                Button("Open UnlikeOtherAI") {
                    openHelpURL("https://unlikeotherai.com")
                }
            }

            if UIDevice.current.userInterfaceIdiom == .pad {
                CommandGroup(after: .toolbar) {
                    Button {
                        selectViewportPreset("")
                    } label: {
                        if iPadMobileStagePresetID.isEmpty {
                            Label("Full Width", systemImage: "checkmark")
                        } else {
                            Text("Full Width")
                        }
                    }

                    Divider()

                    ForEach(availableViewMenuPresets) { preset in
                        Button {
                            selectViewportPreset(preset.id)
                        } label: {
                            if iPadMobileStagePresetID == preset.id {
                                Label(preset.menuLabel, systemImage: "checkmark")
                            } else {
                                Text(preset.menuLabel)
                            }
                        }
                    }

                    if availableViewMenuPresets.isEmpty {
                        Button("No Viewports Available") {}
                            .disabled(true)
                    }
                }
            }
        }
    }

    private func startServices() {
        serverState.startHTTPServer()
        serverState.ensureMDNSAdvertising()
        ExternalDisplayManager.shared.startMonitoring()
        if environment["KELPIE_DEBUG_ATTACH_LOCAL_TV"] == "1",
           !ExternalDisplayManager.shared.isConnected {
            ExternalDisplayManager.shared.attachDebugLocalTV()
        }
        #if DEBUG
        AppRevealSetup.configure()
        #endif
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            serverState.ensureMDNSAdvertising()
        case .background:
            serverState.stopMDNS()
            SessionStore.save(tabs: tabStore.tabs, activeID: tabStore.activeBrowserTabID)
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func openHelpURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        UIApplication.shared.open(url)
    }

    private var availableViewMenuPresets: [TabletViewportPreset] {
        let availableIDs = Set(currentTabletViewportAvailablePresetIDs())
        return tabletViewportPresets.filter { availableIDs.contains($0.id) }
    }

    private func selectViewportPreset(_ presetID: String) {
        NotificationCenter.default.post(
            name: .selectViewportPreset,
            object: nil,
            userInfo: ["presetId": presetID]
        )
    }
}
