import SwiftUI
#if DEBUG
import AppReveal
#endif
import Darwin

extension Notification.Name {
    static let showWelcomeCard = Notification.Name("com.kelpie.browser.macos.show-welcome-card")
}

enum WelcomeCardPresentationSource: String {
    case automatic
    case helpMenu
}

struct BrowserCommandActions {
    let hardReload: () -> Void
}

@MainActor
final class BrowserCommandRouter {
    static let shared = BrowserCommandRouter()

    private weak var activeWindow: NSWindow?
    private var activeActions: BrowserCommandActions?

    private init() {}

    func activate(window: NSWindow, actions: BrowserCommandActions) {
        activeWindow = window
        activeActions = actions
    }

    func update(window: NSWindow, actions: BrowserCommandActions) {
        guard activeWindow === window else { return }
        activeActions = actions
    }

    func deactivate(window: NSWindow) {
        guard activeWindow === window else { return }
        activeWindow = nil
        activeActions = nil
    }

    func hardReload() {
        activeActions?.hardReload()
    }
}

struct BrowserCommandBridge: NSViewRepresentable {
    let actions: BrowserCommandActions

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            context.coordinator.attach(window: window)
            context.coordinator.update(actions: actions, for: window)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var observedWindow: NSWindow?
        private var didBecomeKeyObserver: NSObjectProtocol?
        private var didResignKeyObserver: NSObjectProtocol?
        private var willCloseObserver: NSObjectProtocol?
        private var actions: BrowserCommandActions?

        deinit {
            if let didBecomeKeyObserver {
                NotificationCenter.default.removeObserver(didBecomeKeyObserver)
            }
            if let didResignKeyObserver {
                NotificationCenter.default.removeObserver(didResignKeyObserver)
            }
            if let willCloseObserver {
                NotificationCenter.default.removeObserver(willCloseObserver)
            }
        }

        func attach(window: NSWindow) {
            guard observedWindow !== window else { return }

            if let didBecomeKeyObserver {
                NotificationCenter.default.removeObserver(didBecomeKeyObserver)
            }
            if let didResignKeyObserver {
                NotificationCenter.default.removeObserver(didResignKeyObserver)
            }
            if let willCloseObserver {
                NotificationCenter.default.removeObserver(willCloseObserver)
            }

            observedWindow = window
            didBecomeKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window, let actions = self.actions else { return }
                BrowserCommandRouter.shared.activate(window: window, actions: actions)
            }
            didResignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                guard let window else { return }
                BrowserCommandRouter.shared.deactivate(window: window)
            }
            willCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                guard let window else { return }
                BrowserCommandRouter.shared.deactivate(window: window)
            }
        }

        func update(actions: BrowserCommandActions, for window: NSWindow) {
            self.actions = actions
            if window.isKeyWindow {
                BrowserCommandRouter.shared.activate(window: window, actions: actions)
            } else {
                BrowserCommandRouter.shared.update(window: window, actions: actions)
            }
        }
    }
}

private struct BrowserCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Window") {
                openNewWindow()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button("Hard Refresh") {
                BrowserCommandRouter.shared.hardReload()
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandGroup(after: .windowArrangement) {
            Button("Toggle Full Screen") {
                toggleFullScreenForActiveWindow()
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandGroup(after: .help) {
            Button("Show Welcome Screen") {
                NotificationCenter.default.post(
                    name: .showWelcomeCard,
                    object: WelcomeCardPresentationSource.helpMenu.rawValue
                )
            }

            Divider()

            Button("Open Kelpie Website") {
                openHelpURL("https://unlikeotherai.github.io/kelpie")
            }

            Button("Open GitHub Repository") {
                openHelpURL("https://github.com/UnlikeOtherAI/kelpie")
            }

            Button("Open UnlikeOtherAI") {
                openHelpURL("https://unlikeotherai.com")
            }
        }
    }

    private func openNewWindow() {
        KelpieApp.openNewWindow()
    }

    private func openHelpURL(_ value: String) {
        KelpieApp.openHelpURL(value)
    }

    private func toggleFullScreenForActiveWindow() {
        KelpieApp.toggleFullScreenForActiveWindow()
    }
}

@main
struct KelpieApp: App {
    @StateObject private var browserState = BrowserState()
    @StateObject private var rendererState = RendererState()
    @StateObject private var serverState: ServerState

    init() {
        let launchPort = Self.launchPortArgument() ?? 8420
        _serverState = StateObject(wrappedValue: ServerState(port: UInt16(launchPort)))
        _ = AIState.shared
    }

    var body: some Scene {
        WindowGroup {
            BrowserView(
                browserState: browserState,
                serverState: serverState,
                rendererState: rendererState,
                viewportState: serverState.viewportState
            )
            .onAppear { startServices() }
            .frame(
                minWidth: ViewportState.minimumShellSize.width,
                minHeight: ViewportState.minimumShellSize.height
            )
        }
        .commands {
            BrowserCommands()
        }
    }

    private func startServices() {
        serverState.rendererState = rendererState
        serverState.startHTTPServer()
        #if DEBUG
        if Self.canBind(port: 8421) {
            AppReveal.start(port: 8421)
        } else {
            print("[KelpieApp] Skipping AppReveal start because port 8421 is already in use")
        }
        #endif
    }

    fileprivate static func openNewWindow() {
        let newBrowserState = BrowserState()
        let newServerState = ServerState()
        let newRendererState = RendererState()

        let contentView = BrowserView(
            browserState: newBrowserState,
            serverState: newServerState,
            rendererState: newRendererState,
            viewportState: newServerState.viewportState
        )
        .frame(
            minWidth: ViewportState.minimumShellSize.width,
            minHeight: ViewportState.minimumShellSize.height
        )

        let savedShellSize = ViewportState.persistedShellWindowSize ?? ViewportState.minimumShellSize
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: savedShellSize.width,
                height: savedShellSize.height
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = ViewportState.minimumShellSize
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Start services for the new window
        newServerState.rendererState = newRendererState
        newServerState.startHTTPServer()
    }

    fileprivate static func openHelpURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    fileprivate static func toggleFullScreenForActiveWindow() {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        window?.toggleFullScreen(nil)
    }

    private static func launchPortArgument() -> Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let portIndex = arguments.firstIndex(of: "--port"),
              arguments.indices.contains(portIndex + 1),
              let port = Int(arguments[portIndex + 1]) else {
            return nil
        }
        return port
    }

    private static func canBind(port: UInt16) -> Bool {
        let fd = socket(AF_INET6, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = port.bigEndian
        address.sin6_addr = in6addr_any

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
            }
        }
    }
}
