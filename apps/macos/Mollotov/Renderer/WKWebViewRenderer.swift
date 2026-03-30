import AppKit
import WebKit

/// WKWebView-based renderer conforming to RendererEngine (Safari/WebKit).
@MainActor
final class WKWebViewRenderer: NSObject, RendererEngine, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    let engineName = "webkit"

    private let webView: WKWebView
    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?

    // MARK: - Navigation state (published via onStateChange)
    private(set) var currentURL: URL?
    private(set) var currentTitle: String = ""
    private(set) var isLoading: Bool = false
    private(set) var canGoBack: Bool = false
    private(set) var canGoForward: Bool = false
    private(set) var estimatedProgress: Double = 0.0

    var onStateChange: (() -> Void)?
    var onScriptMessage: ((_ name: String, _ body: [String: Any]) -> Void)?

    override init() {
        let config = WKWebViewConfiguration()

        let ucc = config.userContentController
        // Inject network bridge FIRST (saves postMessage ref before console bridge masks messageHandlers)
        ucc.addUserScript(WKWebViewRenderer.networkBridgeScript)
        ucc.addUserScript(WKWebViewRenderer.consoleBridgeScript)

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)

        super.init()

        ucc.add(self, name: "mollotovNetwork")
        ucc.add(self, name: "mollotovConsole")

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        setupObservations()
    }

    // MARK: - RendererEngine

    func makeView() -> NSView { webView }

    func load(url: URL) {
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func evaluateJS(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    func allCookies() async -> [HTTPCookie] {
        await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
    }

    func setCookies(_ cookies: [HTTPCookie]) async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in cookies {
            await store.setCookie(cookie)
        }
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        await webView.configuration.websiteDataStore.httpCookieStore.deleteCookie(cookie)
    }

    func deleteAllCookies() async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let all = await store.allCookies()
        for cookie in all {
            await store.deleteCookie(cookie)
        }
    }

    func takeSnapshot() async throws -> NSImage {
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        return try await webView.takeSnapshot(configuration: config)
    }

    // MARK: - KVO

    private func setupObservations() {
        progressObservation = webView.observe(\.estimatedProgress) { [weak self] wv, _ in
            Task { @MainActor in
                self?.estimatedProgress = wv.estimatedProgress
                self?.onStateChange?()
            }
        }
        titleObservation = webView.observe(\.title) { [weak self] wv, _ in
            Task { @MainActor in
                self?.currentTitle = wv.title ?? ""
                self?.onStateChange?()
            }
        }
        urlObservation = webView.observe(\.url) { [weak self] wv, _ in
            Task { @MainActor in
                self?.currentURL = wv.url
                self?.onStateChange?()
            }
        }
        loadingObservation = webView.observe(\.isLoading) { [weak self] wv, _ in
            Task { @MainActor in
                self?.isLoading = wv.isLoading
                self?.onStateChange?()
            }
        }
        backObservation = webView.observe(\.canGoBack) { [weak self] wv, _ in
            Task { @MainActor in
                self?.canGoBack = wv.canGoBack
                self?.onStateChange?()
            }
        }
        forwardObservation = webView.observe(\.canGoForward) { [weak self] wv, _ in
            Task { @MainActor in
                self?.canGoForward = wv.canGoForward
                self?.onStateChange?()
            }
        }
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        Task { @MainActor in
            onScriptMessage?(message.name, body)
        }
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.isLoading = false
            self.onStateChange?()
        }
    }

    // MARK: - WKUIDelegate

    nonisolated func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // MARK: - Bridge Scripts (same JS as iOS)

    // These are the same bridge scripts from iOS ConsoleHandler.bridgeScript
    // and NetworkBridge.bridgeScript, copied here because they reference
    // WKUserScript which is specific to this renderer.
    static let consoleBridgeScript: WKUserScript = ConsoleHandler.bridgeScript
    static let networkBridgeScript: WKUserScript = NetworkBridge.bridgeScript
}
