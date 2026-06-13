import AppKit
import WebKit

private struct WKRendererTimeoutError: LocalizedError, Sendable {
    let operation: String

    var errorDescription: String? {
        "\(operation) timed out"
    }
}

private struct WKRendererNilResultError: LocalizedError, Sendable {
    let operation: String

    var errorDescription: String? {
        "\(operation) returned no result"
    }
}

private final class WKRendererCompletion<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<T, Error>

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()
        continuation.resume(with: result)
    }
}

/// WKWebView-based renderer conforming to RendererEngine (Safari/WebKit).
@MainActor
final class WKWebViewRenderer: NSObject, RendererEngine, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    let engineName = "webkit"
    nonisolated private static let operationTimeoutSeconds: TimeInterval = 8

    private let webView: WKWebView
    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?
    private var documentNavigationStart: Date?
    private var capturedDocumentResponseURL: String?

    // MARK: - Navigation state (published via onStateChange)
    private(set) var currentURL: URL?
    private(set) var currentTitle: String = ""
    private(set) var isLoading: Bool = false
    private(set) var canGoBack: Bool = false
    private(set) var canGoForward: Bool = false
    private(set) var estimatedProgress: Double = 0.0

    /// Most recent main-frame load failure, cleared at the start of each new
    /// provisional navigation. Read by `NavigationHandler` to surface
    /// NAVIGATION_ERROR for DNS failures / connection-refused / interrupted
    /// loads instead of a false success or TIMEOUT. Lives on the renderer (not
    /// HandlerContext) because macOS has one WKWebView per tab and the
    /// navigation delegate is the renderer itself.
    private(set) var lastNavigationError: String?

    /// Per-renderer JavaScript dialog store. macOS genuinely supports multiple
    /// windows/tabs, each with its own WKWebView; a process-wide singleton would
    /// let a dialog in one window dismiss a pending dialog in another. The
    /// WKUIDelegate panels below enqueue into THIS instance, and handlers reach
    /// it via `HandlerContext.dialogState(windowId:tabId:)`.
    let dialogState = DialogState()

    var onStateChange: (() -> Void)?
    var onScriptMessage: ((_ name: String, _ body: [String: Any]) -> Void)?

    override init() {
        let config = WKWebViewConfiguration()

        let ucc = config.userContentController
        // Inject network bridge FIRST (saves postMessage ref before console bridge masks messageHandlers)
        ucc.addUserScript(Self.networkBridgeScript)
        ucc.addUserScript(Self.webSocketBridgeScript)
        ucc.addUserScript(Self.consoleBridgeScript)

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)

        super.init()

        ucc.add(self, name: "kelpieNetwork")
        ucc.add(self, name: "kelpieConsole")
        ucc.add(self, name: "kelpie3DSnapshot")

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        setupObservations()
    }

    // MARK: - RendererEngine

    func makeView() -> NSView { webView }

    /// Breaks the retain cycle between the renderer and WKUserContentController.
    /// Must be called before the owning Tab is released.
    func invalidate() {
        let ucc = webView.configuration.userContentController
        ucc.removeScriptMessageHandler(forName: "kelpieNetwork")
        ucc.removeScriptMessageHandler(forName: "kelpieConsole")
        ucc.removeScriptMessageHandler(forName: "kelpie3DSnapshot")
    }

    func load(url: URL) {
        lastNavigationError = nil
        webView.load(URLRequest(url: url))
    }

    /// Clears any captured navigation error. Used by `NavigationHandler` to start
    /// a navigation from a clean slate before driving `load(url:)`.
    func clearNavigationError() {
        lastNavigationError = nil
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func hardReload() { webView.reloadFromOrigin() }

    func evaluateJS(_ script: String) async throws -> Any? {
        try await withWebKitTimeout("JavaScript evaluation") { completion in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(result))
                }
            }
        }
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
        let hostBounds = webView.superview?.bounds ?? .zero
        let snapshotBounds = hostBounds.width > 0 && hostBounds.height > 0 ? hostBounds : webView.bounds
        config.rect = CGRect(
            origin: .zero,
            size: CGSize(
                width: snapshotBounds.width.rounded(),
                height: snapshotBounds.height.rounded()
            )
        )
        return try await withWebKitTimeout("Snapshot capture") { completion in
            webView.takeSnapshot(with: config) { image, error in
                if let error {
                    completion(.failure(error))
                } else if let image {
                    completion(.success(image))
                } else {
                    completion(.failure(WKRendererNilResultError(operation: "Snapshot capture")))
                }
            }
        }
    }

    private func withWebKitTimeout<T>(
        _ operation: String,
        _ start: (@escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let completion = WKRendererCompletion(continuation)
            start { result in
                completion.resume(with: result)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.operationTimeoutSeconds) {
                completion.resume(with: .failure(WKRendererTimeoutError(operation: operation)))
            }
        }
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

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        onScriptMessage?(message.name, body)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.isLoading = false
        self.onStateChange?()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // Each new provisional navigation starts clean — clear any error captured
        // by a superseded load so a cancelled-then-successful sequence is not fatal.
        self.lastNavigationError = nil
        self.documentNavigationStart = Date()
        self.capturedDocumentResponseURL = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.recordNavigationFailure(error)
        self.isLoading = false
        self.onStateChange?()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        self.recordNavigationFailure(error)
        self.isLoading = false
        self.onStateChange?()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        self.recordMainDocumentResponse(navigationResponse)
        decisionHandler(.allow)
    }

    /// Captures a real main-frame load failure, ignoring benign codes that do
    /// not represent a navigation error: `NSURLErrorCancelled` (a superseded
    /// load, e.g. a redirect) and `NSURLErrorFrameLoadInterrupted` (commonly
    /// fired when a response is handed off to a download or a custom scheme).
    private func recordNavigationFailure(_ error: Error) {
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled || ns.code == NSURLErrorFrameLoadInterrupted { return }
        self.lastNavigationError = error.localizedDescription
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // MARK: - JavaScript dialogs

    // Instead of presenting a native NSAlert (which would block the WebView and
    // require a human click), each panel is captured into THIS renderer's
    // DialogState. The WebKit completion handler is suspended inside a
    // PendingDialog until either an auto-handler resolves it immediately or
    // `handle-dialog` is called over HTTP/MCP for this tab. Per-renderer state
    // keeps multi-window dialogs isolated. This mirrors the iOS
    // WebViewCoordinator semantics exactly.

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let dialog = DialogState.PendingDialog(type: .alert, message: message, defaultText: nil) { _ in
            completionHandler()
        }
        dialogState.enqueue(dialog)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let dialog = DialogState.PendingDialog(type: .confirm, message: message, defaultText: nil) { result in
            completionHandler(result != nil)
        }
        dialogState.enqueue(dialog)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let dialog = DialogState.PendingDialog(type: .prompt, message: prompt, defaultText: defaultText) { result in
            completionHandler(result)
        }
        dialogState.enqueue(dialog)
    }

    // MARK: - Bridge Scripts (same JS as iOS)

    // These are the same bridge scripts from iOS ConsoleHandler.bridgeScript
    // and NetworkBridge.bridgeScript, copied here because they reference
    // WKUserScript which is specific to this renderer.
    static let consoleBridgeScript: WKUserScript = ConsoleHandler.bridgeScript
    static let networkBridgeScript: WKUserScript = NetworkBridge.bridgeScript
    static let webSocketBridgeScript: WKUserScript = WebSocketBridge.bridgeScript

    private func recordMainDocumentResponse(_ navigationResponse: WKNavigationResponse) {
        guard navigationResponse.isForMainFrame,
              let response = navigationResponse.response as? HTTPURLResponse,
              let url = response.url?.absoluteString,
              capturedDocumentResponseURL != url else {
            return
        }

        let contentType = response.mimeType
            ?? response.value(forHTTPHeaderField: "Content-Type")
            ?? "text/html"
        let size = Int(response.expectedContentLength)
        let responseHeaders = response.allHeaderFields.reduce(into: [String: String]()) { headers, item in
            headers[String(describing: item.key)] = String(describing: item.value)
        }

        NetworkTrafficStore.shared.appendDocumentNavigation(
            url: url,
            statusCode: response.statusCode,
            contentType: contentType,
            responseHeaders: responseHeaders,
            size: size > 0 ? size : 0,
            startedAt: documentNavigationStart ?? Date()
        )

        capturedDocumentResponseURL = url
    }
}
