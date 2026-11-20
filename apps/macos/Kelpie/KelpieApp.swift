import SwiftUI
import KelpieBrowser

struct KelpieApp: App {
    @StateObject private var browser = KelpieBrowserSession.standalone()
    #if !KELPIE_WEBKIT_ONLY
    @StateObject private var updates = AppUpdates()
    #endif

    init() {
        #if DEBUG
        Task { @MainActor in KelpieDiagnostics.start() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            KelpieBrowserView(session: browser, ownsWindowChrome: true)
                #if !KELPIE_WEBKIT_ONLY
                .modifier(AppUpdatePresentation(updates: updates))
                #endif
        }
            .commands { KelpieBrowserCommands(session: browser) }
    }
}
