import AppKit
import AppReveal
import KelpieBrowser
import SwiftUI

@main
struct EmbeddingHost: App {
    var body: some Scene {
        WindowGroup { HostView().frame(minWidth: 920, minHeight: 650) }
    }
}

private struct HostView: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> HostController { HostController() }
    func updateNSViewController(_ controller: HostController, context: Context) {}
}

@MainActor
private final class HostController: NSViewController {
    private let container = NSView()
    private let status = NSTextField(labelWithString: "Host ready")
    private var session: KelpieBrowserSession?
    private var surface: KelpieBrowserSurface?
    private var browser: NSViewController?
    private var other: NSWindow?
    private var moved = false
    private var closingObserver: NSObjectProtocol?

    override func loadView() {
        view = NSView()
        let controls = NSStackView(views: [
            NSButton(title: "Open browser", target: self, action: #selector(openBrowser)),
            NSButton(title: "Move browser", target: self, action: #selector(moveBrowser)),
            NSButton(title: "Close browser", target: self, action: #selector(closeBrowser)),
            status
        ])
        controls.orientation = .horizontal
        controls.spacing = 12
        controls.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        view.addSubview(container)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            controls.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            container.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.title = "Kelpie embedding host"
        AppReveal.start()
        if closingObserver == nil, let window = view.window {
            closingObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.retireBrowser() } }
        }
    }

    deinit {
        if let closingObserver { NotificationCenter.default.removeObserver(closingObserver) }
    }

    private func retireBrowser() {
        session?.close()
        browser?.view.removeFromSuperview()
        browser?.removeFromParent()
        browser = nil
        surface = nil
        session = nil
        other?.close()
        other = nil
    }

    @objc private func openBrowser() {
        if browser == nil {
            let provider = KelpieUOASession(
                subject: nil,
                request: { _, _, _, _ in throw URLError(.userAuthenticationRequired) },
                settingsSocket: { _, _ in throw URLError(.userAuthenticationRequired) },
                signIn: { [weak self] in self?.status.stringValue = "Host sign-in requested" },
                signOut: { [weak self] in self?.status.stringValue = "Host sign-out requested" }
            )
            let session = KelpieBrowserSession(uoaSession: provider, localControlEnabled: false)
            let surface = session.makeSurface()
            self.session = session
            self.surface = surface
            browser = surface.makeViewController()
        }
        attach(to: container)
        moved = false
        status.stringValue = "Browser attached"
    }

    @objc private func moveBrowser() {
        guard browser != nil else { return }
        if moved {
            attach(to: container)
            status.stringValue = "Browser returned"
        } else {
            if other == nil {
                let window = NSWindow(
                    contentRect: NSRect(x: 120, y: 120, width: 920, height: 650),
                    styleMask: [.titled, .closable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                window.title = "Second host window"
                window.isReleasedWhenClosed = false
                let controller = NSViewController()
                controller.view = NSView(frame: window.contentLayoutRect)
                window.contentViewController = controller
                other = window
            }
            if let destination = other?.contentView {
                attach(to: destination)
                other?.makeKeyAndOrderFront(nil)
                status.stringValue = "Browser moved"
            }
        }
        moved.toggle()
    }

    @objc private func closeBrowser() {
        browser?.view.removeFromSuperview()
        browser?.removeFromParent()
        status.stringValue = "Browser detached; host remains open"
    }

    private func attach(to destination: NSView) {
        guard let browser else { return }
        browser.view.removeFromSuperview()
        browser.removeFromParent()
        addChild(browser)
        browser.view.frame = destination.bounds
        browser.view.autoresizingMask = [.width, .height]
        destination.addSubview(browser.view)
    }
}
