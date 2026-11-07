import SwiftUI
import KelpieBrowser

@main
struct KelpieApp: App {
    @StateObject private var browser = KelpieBrowserSession()

    var body: some Scene {
        WindowGroup { KelpieBrowserView(session: browser) }
            .commands { KelpieBrowserCommands(session: browser) }
    }
}
