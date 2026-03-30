import SwiftUI

@main
struct MollotovApp: App {
    @StateObject private var browserState = BrowserState()
    @StateObject private var serverState = ServerState()
    @StateObject private var rendererState = RendererState()

    init() {
        FontAwesome.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            BrowserView(
                browserState: browserState,
                serverState: serverState,
                rendererState: rendererState
            )
            .onAppear { startServices() }
            .frame(minWidth: 320, minHeight: 480)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Window") {
                    openNewWindow()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    private func startServices() {
        serverState.rendererState = rendererState
        serverState.startHTTPServer()
        serverState.startMDNS()
    }

    private func openNewWindow() {
        let newBrowserState = BrowserState()
        let newServerState = ServerState()
        let newRendererState = RendererState()

        let contentView = BrowserView(
            browserState: newBrowserState,
            serverState: newServerState,
            rendererState: newRendererState
        )
        .frame(minWidth: 320, minHeight: 480)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mollotov"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Start services for the new window
        newServerState.rendererState = newRendererState
        newServerState.startHTTPServer()
    }
}
