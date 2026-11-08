import AppKit

/// Adds browser commands only while a containing window holds an active SDK view.
@MainActor
final class EmbeddedBrowserMenu: NSObject, NSMenuItemValidation {
    private weak var session: KelpieBrowserSession?
    private var observers: [NSObjectProtocol] = []
    private var installed: NSMenuItem?
    private var keyMonitor: Any?

    init(session: KelpieBrowserSession) {
        self.session = session
        super.init()
        // SwiftUI host commands can win duplicate menu equivalents such as Cmd+W.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })
        }
    }

    func refresh() {
        guard let session, !session.isClosed, let window = NSApp.keyWindow, session.containsBrowser(in: window),
              let menu = NSApp.mainMenu else { remove(); return }
        if installed?.menu === menu { return }
        remove()
        let commands = NSMenu(title: "Browser")
        let groups = [BrowserMenuCommand.tabs, BrowserMenuCommand.tools, [.fullScreen], [.welcome], BrowserMenuCommand.help]
        for (index, group) in groups.enumerated() {
            if index > 0 { commands.addItem(.separator()) }
            for command in group {
                let item = NSMenuItem(title: command.title, action: #selector(invoke(_:)), keyEquivalent: command.key.map(String.init) ?? "")
                item.target = self
                item.representedObject = command.rawValue
                item.keyEquivalentModifierMask = command.key == nil ? [] : .command
                commands.addItem(item)
            }
        }
        let item = NSMenuItem(title: "Browser", action: nil, keyEquivalent: "")
        item.submenu = commands
        menu.insertItem(item, at: min(1, menu.items.count))
        installed = item
    }

    func close() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        remove()
    }

    private func remove() {
        if let installed { installed.menu?.removeItem(installed) }
        installed = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let session, !session.isClosed, !session.serverState.isScriptRecording,
              let window = NSApp.keyWindow, event.window === window, window.attachedSheet == nil,
              session.containsBrowser(in: window), let menu = installed?.submenu else { return false }
        return menu.performKeyEquivalent(with: event)
    }

    @objc private func invoke(_ sender: NSMenuItem) {
        guard validateMenuItem(sender), let session, let name = sender.representedObject as? String,
              let command = BrowserMenuCommand(rawValue: name) else { return }
        command.perform(in: session)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let session, !session.isClosed, let window = NSApp.keyWindow, session.containsBrowser(in: window) else { return false }
        return !session.serverState.isScriptRecording
    }
}
