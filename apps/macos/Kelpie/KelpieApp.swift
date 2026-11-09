import SwiftUI
import KelpieBrowser

struct KelpieApp: App {
    @StateObject private var browser = KelpieBrowserSession.standalone()

    init() {
        #if DEBUG
        Task { @MainActor in KelpieDiagnostics.start() }
        #endif
    }

    var body: some Scene {
        WindowGroup { KelpieBrowserView(session: browser, ownsWindowChrome: true) }
            .commands { KelpieBrowserCommands(session: browser) }
    }
}
