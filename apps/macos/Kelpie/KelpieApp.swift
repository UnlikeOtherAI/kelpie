import SwiftUI
import KelpieBrowser

struct KelpieApp: App {
    @StateObject private var browser = KelpieBrowserSession.standalone()
    @StateObject private var updates = AppUpdates()

    init() {
        #if DEBUG
        Task { @MainActor in KelpieDiagnostics.start() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            KelpieBrowserView(session: browser, ownsWindowChrome: true)
                .modifier(AppUpdatePresentation(updates: updates))
        }
            .commands { KelpieBrowserCommands(session: browser) }
    }
}
