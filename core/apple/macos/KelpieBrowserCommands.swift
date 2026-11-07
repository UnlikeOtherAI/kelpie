import SwiftUI

public struct KelpieBrowserCommands: Commands {
    private let session: KelpieBrowserSession

    public init(session: KelpieBrowserSession) {
        self.session = session
        self.serverState = session.serverState
        self.browserState = session.browserState
        self.rendererState = session.rendererState
    }
    @ObservedObject var serverState: ServerState
    let browserState: BrowserState
    let rendererState: RendererState

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                BrowserCommandRouter.shared.newTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(serverState.isScriptRecording)

            Button("Close Tab") {
                BrowserCommandRouter.shared.closeTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(serverState.isScriptRecording)

            Button("New Window") {
                openNewWindow()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(serverState.isScriptRecording)
        }

        CommandGroup(after: .toolbar) {
            Button("Add bookmark") {
                BrowserCommandRouter.shared.addBookmark()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(serverState.isScriptRecording)

            Button("Hard Refresh") {
                BrowserCommandRouter.shared.hardReload()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(serverState.isScriptRecording)
        }

        CommandGroup(after: .windowArrangement) {
            Button("Toggle Full Screen") {
                toggleFullScreenForActiveWindow()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(serverState.isScriptRecording)
        }

        CommandGroup(after: .help) {
            Button("Show Welcome Screen") {
                NotificationCenter.default.post(
                    name: .showWelcomeCard,
                    object: WelcomeCardPresentationSource.helpMenu.rawValue
                )
            }
            .disabled(serverState.isScriptRecording)

            Divider()

            Button("Open Kelpie Website") {
                openHelpURL("https://unlikeotherai.github.io/kelpie")
            }
            .disabled(serverState.isScriptRecording)

            Button("Open GitHub Repository") {
                openHelpURL("https://github.com/UnlikeOtherAI/kelpie")
            }
            .disabled(serverState.isScriptRecording)

            Button("Open UnlikeOtherAI") {
                openHelpURL("https://unlikeotherai.com")
            }
            .disabled(serverState.isScriptRecording)
        }
    }

    private func openNewWindow() {
        session.openWindow()
    }

    private func openHelpURL(_ value: String) {
        if let url = URL(string: value) { NSWorkspace.shared.open(url) }
    }

    private func toggleFullScreenForActiveWindow() {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
    }
}

