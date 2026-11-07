import SwiftUI

extension Notification.Name {
    static let showWelcomeCard = Notification.Name("com.kelpie.browser.macos.show-welcome-card")
}

enum WelcomeCardPresentationSource: String {
    case automatic
    case helpMenu
}

struct BrowserCommandActions {
    let hardReload: () -> Void
    let newTab: () -> Void
    let closeTab: () -> Void
    let addBookmark: () -> Void
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

    func newTab() {
        activeActions?.newTab()
    }

    func addBookmark() {
        activeActions?.addBookmark()
    }

    func closeTab() {
        activeActions?.closeTab()
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
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window, let actions = self.actions else { return }
                    BrowserCommandRouter.shared.activate(window: window, actions: actions)
                }
            }
            didResignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                Task { @MainActor [weak window] in
                    guard let window else { return }
                    BrowserCommandRouter.shared.deactivate(window: window)
                }
            }
            willCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                Task { @MainActor [weak window] in
                    guard let window else { return }
                    BrowserCommandRouter.shared.deactivate(window: window)
                }
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

