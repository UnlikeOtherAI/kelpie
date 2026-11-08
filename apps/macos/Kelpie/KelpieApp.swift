import SwiftUI
import KelpieBrowser

@main
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
