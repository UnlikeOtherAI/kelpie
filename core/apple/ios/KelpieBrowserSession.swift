import SwiftUI
import UIKit

/// Keeps the complete browser alive while its host chooses where to present it.
@MainActor
public final class KelpieBrowserSession: ObservableObject {
    let browserState = BrowserState()
    let serverState: ServerState
    let tabStore: TabStore
    private let localControlEnabled: Bool
    private let externalDisplaysEnabled: Bool
    private var started = false
    private var closed = false

    public init(uoaSession: KelpieUOASession? = nil, port: UInt16 = 8420, localControlEnabled: Bool = true, externalDisplaysEnabled: Bool = false) {
        let server = ServerState(port: port)
        serverState = server
        tabStore = TabStore(handlerContext: server.handlerContext)
        server.tabStore = tabStore
        self.localControlEnabled = localControlEnabled
        if let uoaSession { UOAAccount.shared.useHostSession(uoaSession) }
        self.externalDisplaysEnabled = externalDisplaysEnabled
    }

    public static var supportedOrientations: UIInterfaceOrientationMask { OrientationManager.shared.lock }

    public var websiteDataIsPersistent: Bool { KelpieWebsiteData.store.isPersistent }

    public func start() {
        guard !started, !closed else { return }
        started = true
        serverState.startHTTPServer(listen: localControlEnabled)
        NessieConnection.shared.start(context: serverState.handlerContext)
        if localControlEnabled { serverState.ensureMDNSAdvertising() }
        if externalDisplaysEnabled {
            let displays = ExternalDisplayManager.shared
            displays.startMonitoring()
            if ProcessInfo.processInfo.environment["KELPIE_DEBUG_ATTACH_LOCAL_TV"] == "1", !displays.isConnected {
                displays.attachDebugLocalTV()
            }
        }
        OpenAIEndpointMonitor.shared.start()
        UOAAccount.shared.restoreSession()
    }

    public func setScenePhase(_ phase: ScenePhase) {
        guard !closed else { return }
        switch phase {
        case .active:
            BookmarkStore.shared.refreshAccountBookmarks()
            NessieConnection.shared.setForeground(true)
            if localControlEnabled { serverState.ensureMDNSAdvertising() }
        case .background:
            NetworkTrafficStore.shared.flush()
            NessieConnection.shared.setForeground(false)
            serverState.stopMDNS()
            SessionStore.save(tabs: tabStore.tabs, activeID: tabStore.activeBrowserTabID)
        case .inactive:
            NessieConnection.shared.setForeground(false)
        @unknown default: break
        }
    }

    /// Terminal close; presentation moves retain this session instead.
    public func close() {
        guard !closed else { return }
        closed = true
        NessieConnection.shared.detach(context: serverState.handlerContext)
        serverState.stop()
        _ = serverState.scriptPlaybackState.requestAbort()
        serverState.router.invalidateAllBrowserReferences()
        NetworkTrafficStore.shared.flush()
        tabStore.closeAll()
        if externalDisplaysEnabled { ExternalDisplayManager.shared.detach() }
    }

    public func makeViewController() -> UIViewController {
        UIHostingController(rootView: KelpieBrowserView(session: self))
    }
}

@MainActor
public struct KelpieBrowserView: View {
    @ObservedObject private var session: KelpieBrowserSession
    @Environment(\.scenePhase) private var scenePhase

    public init(session: KelpieBrowserSession) { self.session = session }

    public var body: some View {
        BrowserView(browserState: session.browserState, serverState: session.serverState, tabStore: session.tabStore)
            .onAppear { session.start(); session.setScenePhase(scenePhase) }
            .onChange(of: scenePhase) { session.setScenePhase($0) }
    }
}
