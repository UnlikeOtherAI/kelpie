import SwiftUI

@main
struct MollotovApp: App {
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
        #if DEBUG
        AppRevealSetup.configure()
        #endif
    }
}
