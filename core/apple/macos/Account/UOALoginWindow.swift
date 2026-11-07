import AppKit
import WebKit

/// macOS UOA login surface: a standalone window hosting `UOALoginWebController`. The window title
/// always names the real origin, and Cancel is an AppKit `NSButton` because the window contains a
/// WebView (see AGENTS.md). Closing the window is the same as Cancel.
@MainActor
final class UOALoginWindowController: NSObject, NSWindowDelegate, UOALoginSurface {
    /// How long the login waits for Chromium's cookies before loading without them.
    private static let seedTimeout: Duration = .seconds(3)

    private let window: NSWindow
    private let web: UOALoginWebController
    private var finish: ((UOALoginResult) -> Void)?
    private var cookieBaseline: [HTTPCookie] = []
    private var loadStarted = false

    static func present(_ url: URL, finish: @escaping (UOALoginResult) -> Void) -> UOALoginSurface {
        let controller = UOALoginWindowController(url: url, finish: finish)
        controller.show()
        controller.start(url)
        return controller
    }

    private init(url: URL, finish: @escaping (UOALoginResult) -> Void) {
        web = UOALoginWebController(dataStore: .default(), userAgent: WKWebViewRenderer.safariUserAgent)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.finish = finish
        super.init()
        configureWindow(title: UOALoginNavigation.title(for: url))
        web.onURLChange = { [weak self] url in self?.window.title = UOALoginNavigation.title(for: url) }
        web.onCallback = { [weak self] url in self?.end(.callback(url)) }
        web.onFailure = { [weak self] in self?.end(.failed) }
    }

    func close() {
        finish = nil
        dismiss()
    }

    func windowWillClose(_ notification: Notification) {
        end(.cancelled)
    }

    // MARK: - Lifecycle

    /// Loads the login page once Chromium's cookies are in the login store, or after the timeout.
    private func start(_ url: URL) {
        Task { [weak self] in
            let baseline = await UOALoginCookies.prepare()
            self?.cookieBaseline = baseline
            self?.beginLoad(url)
        }
        Task { [weak self] in
            try? await Task.sleep(for: Self.seedTimeout)
            self?.beginLoad(url)
        }
    }

    private func beginLoad(_ url: URL) {
        guard !loadStarted, finish != nil else { return }
        loadStarted = true
        web.load(url)
    }

    private func end(_ result: UOALoginResult) {
        guard let finish else { return }
        self.finish = nil
        if case .callback = result {
            let baseline = cookieBaseline
            Task { await UOALoginCookies.share(changesSince: baseline) }
        }
        dismiss()
        finish(result)
    }

    private func dismiss() {
        web.stop()
        window.delegate = nil
        window.close()
    }

    @objc private func cancel(_ sender: Any?) {
        end(.cancelled)
    }

    // MARK: - Window

    private func show() {
        if let parent = NSApp.keyWindow ?? NSApp.mainWindow {
            let frame = parent.frame
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
        } else {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func configureWindow(title: String) {
        window.title = title
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone]
        window.minSize = NSSize(width: 380, height: 480)
        window.contentView = makeContent()
        window.delegate = self
    }

    private func makeContent() -> NSView {
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.bezelStyle = .push
        cancel.setAccessibilityIdentifier("account.login.cancel")
        let separator = NSBox()
        separator.boxType = .separator
        let content = NSView()
        for view in [web.webView, separator, cancel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            web.webView.topAnchor.constraint(equalTo: content.topAnchor),
            web.webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            web.webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.topAnchor.constraint(equalTo: web.webView.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            cancel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 10),
            cancel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            cancel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
        return content
    }
}
