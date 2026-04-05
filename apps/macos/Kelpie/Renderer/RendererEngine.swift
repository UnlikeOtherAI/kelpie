import AppKit
import WebKit

/// Abstraction over WKWebView and CEF. All handlers interact with the browser
/// engine exclusively through this protocol via HandlerContext.
@MainActor
protocol RendererEngine: AnyObject {
    /// The engine identifier used in API responses and mDNS TXT records.
    var engineName: String { get }

    // MARK: - Navigation state
    var currentURL: URL? { get }
    var currentTitle: String { get }
    var isLoading: Bool { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    var estimatedProgress: Double { get }

    // MARK: - Navigation actions
    func load(url: URL)
    func goBack()
    func goForward()
    func reload()
    func hardReload()

    // MARK: - JavaScript
    /// Evaluate JS and return the result. Equivalent to WKWebView.evaluateJavaScript.
    func evaluateJS(_ script: String) async throws -> Any?

    // MARK: - Cookies
    func allCookies() async -> [HTTPCookie]
    func setCookies(_ cookies: [HTTPCookie]) async
    func deleteCookie(_ cookie: HTTPCookie) async
    func deleteAllCookies() async

    // MARK: - Screenshot
    func takeSnapshot() async throws -> NSImage

    // MARK: - View
    /// Returns the NSView to embed in SwiftUI via NSViewRepresentable.
    func makeView() -> NSView

    // MARK: - Renderer switch lifecycle
    /// Called on the outgoing renderer at the start of a switch, before any async work.
    /// Implement to cancel background polling or other activity that would interfere
    /// with the switch. Default: no-op.
    func willDeactivate()
    /// Called on the incoming renderer after the switch completes and it becomes visible.
    /// Default: no-op.
    func didActivate()
    /// Called when the staged viewport changes size or enters/exits staged mode.
    /// Renderers that cannot reliably survive live viewport resizes can rebuild
    /// themselves here. Default: no-op.
    func viewportDidChange()

    // MARK: - Lifecycle callbacks
    /// Called by BrowserView when navigation state changes. Used to sync BrowserState.
    var onStateChange: (() -> Void)? { get set }

    // MARK: - Script message handling (for console/network bridge)
    /// Register a callback for messages from injected bridge scripts.
    var onScriptMessage: ((_ name: String, _ body: [String: Any]) -> Void)? { get set }
}

extension RendererEngine {
    func willDeactivate() {}
    func didActivate() {}
    func viewportDidChange() {}
    func hardReload() { reload() }
}
