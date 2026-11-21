import AppKit
import Combine
import WebKit

/// A secondary WebKit browsing context tied to its opener, with the actual
/// origin in native window chrome and a tab ID for browser control.
@MainActor
final class WKPopupWindow: NSObject, NSWindowDelegate {
    let id = UUID()
    let webView: WKWebView
    var onClose: (() -> Void)?

    private let window: NSWindow
    private let tabStore: TabStore
    private weak var openerWindow: NSWindow?
    private var urlObservation: AnyCancellable?

    init(opener: Tab, configuration: WKWebViewConfiguration, features: WKWindowFeatures) {
        let renderer = WKWebViewRenderer(configuration: configuration)
        let spec = TabSpec(partition: opener.partition, persistent: opener.persistent)
        let tab = Tab(spec: spec, renderer: renderer)
        tab.isStartPage = false
        tabStore = TabStore(isolatedTab: tab)
        webView = renderer.webView

        let parent = opener.renderer.webView.window
        openerWindow = parent
        let screen = parent?.screen ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 750)
        let width = min(max(features.width?.doubleValue ?? 520, 360), available.width)
        let height = min(max(features.height?.doubleValue ?? 680, 360), available.height - 36)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        super.init()

        window.title = "Pop-up"
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: available.midX - width / 2, y: available.midY - window.frame.height / 2))
        window.contentView = webView
        window.delegate = self
        renderer.onClosePopup = { [weak self] in self?.close() }
        urlObservation = tab.$currentURL.sink { [weak self] url in
            self?.setWindowTitle(url)
        }
    }

    func show() {
        WindowRegistry.shared.register(id: id.uuidString, window: window, tabStore: tabStore)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }

    func windowWillClose(_ notification: Notification) {
        let restoreFocus = window.isKeyWindow
        WindowRegistry.shared.unregister(id: id.uuidString)
        tabStore.closeAll()
        if restoreFocus, openerWindow?.isVisible == true { openerWindow?.makeKeyAndOrderFront(nil) }
        onClose?()
    }

    private func setWindowTitle(_ address: String) {
        guard let url = URL(string: address), let scheme = url.scheme, let host = url.host,
              scheme == "https" || scheme == "http" else {
            window.title = "Pop-up"
            return
        }
        let port = url.port.map { ":\($0)" } ?? ""
        window.title = "\(scheme)://\(host)\(port)"
    }
}
