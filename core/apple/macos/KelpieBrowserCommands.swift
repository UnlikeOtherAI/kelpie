import SwiftUI

/// The standalone app and embedded AppKit menus use the same command definitions.
public struct KelpieBrowserCommands: Commands {
    private let session: KelpieBrowserSession
    @ObservedObject private var serverState: ServerState

    public init(session: KelpieBrowserSession) {
        self.session = session
        serverState = session.serverState
    }

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            ForEach(BrowserMenuCommand.tabs) { commandButton($0) }
        }
        CommandGroup(after: .toolbar) {
            ForEach(BrowserMenuCommand.tools) { commandButton($0) }
        }
        CommandGroup(after: .windowArrangement) { commandButton(.fullScreen) }
        CommandGroup(after: .help) {
            commandButton(.welcome)
            Divider()
            ForEach(BrowserMenuCommand.help) { commandButton($0) }
        }
    }

    @ViewBuilder
    private func commandButton(_ command: BrowserMenuCommand) -> some View {
        let button = Button(command.title) { command.perform(in: session) }
            .disabled(serverState.isScriptRecording)
        if let key = command.key { button.keyboardShortcut(KeyEquivalent(key), modifiers: .command) } else { button }
    }
}
