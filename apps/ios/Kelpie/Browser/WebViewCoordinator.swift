import SwiftUI
import WebKit

/// Wraps WKWebView in a UIViewRepresentable for SwiftUI.
struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var browserState: BrowserState
    let handlerContext: HandlerContext?
    let onWebView: (WKWebView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(browserState: browserState, handlerContext: handlerContext)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.processPool = WebViewDefaults.sharedProcessPool
        config.websiteDataStore = WebViewDefaults.sharedWebsiteDataStore

        // Inject bridge scripts — network bridge FIRST (saves postMessage ref before console bridge masks messageHandlers)
        if let handlerContext {
            let ucc = config.userContentController
            ucc.addUserScript(NetworkBridge.bridgeScript)
            ucc.add(handlerContext, name: "kelpieNetwork")
            ucc.addUserScript(ConsoleHandler.bridgeScript)
            ucc.add(handlerContext, name: "kelpieConsole")
            ucc.add(handlerContext, name: "kelpie3DSnapshot")
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        // Use Safari user agent so Google OAuth and similar services don't block us
        webView.customUserAgent = WebViewDefaults.sharedUserAgent

        context.coordinator.webView = webView
        context.coordinator.observe(webView)
        onWebView(webView)

        if let url = URL(string: browserState.currentURL) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Navigation is handled via coordinator methods, not updateUIView
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let browserState: BrowserState
        weak var handlerContext: HandlerContext?
        weak var webView: WKWebView?
        private var progressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?
        private var backObservation: NSKeyValueObservation?
        private var forwardObservation: NSKeyValueObservation?
        private var documentNavigationStart: Date?
        private var capturedDocumentResponseURL: String?

        init(browserState: BrowserState, handlerContext: HandlerContext?) {
            self.browserState = browserState
            self.handlerContext = handlerContext
            super.init()
        }

        func observe(_ webView: WKWebView) {
            guard progressObservation == nil else {
                syncBrowserState(from: webView)
                return
            }

            progressObservation = webView.observe(\.estimatedProgress) { [weak self] wv, _ in
                Task { @MainActor in self?.browserState.progress = wv.estimatedProgress }
            }
            titleObservation = webView.observe(\.title) { [weak self] wv, _ in
                Task { @MainActor in self?.browserState.pageTitle = wv.title ?? "" }
            }
            urlObservation = webView.observe(\.url) { [weak self] wv, _ in
                Task { @MainActor in self?.browserState.currentURL = wv.url?.absoluteString ?? "" }
            }
            loadingObservation = webView.observe(\.isLoading) { [weak self] wv, _ in
                Task { @MainActor in self?.browserState.isLoading = wv.isLoading }
            }
            backObservation = webView.observe(\.canGoBack) { [weak self] wv, _ in
                Task { @MainActor in self?.browserState.canGoBack = wv.canGoBack }
            }
            forwardObservation = webView.observe(\.canGoForward) { [weak self] wv, _ in
                Task { @MainActor in self?.browserState.canGoForward = wv.canGoForward }
            }

            syncBrowserState(from: webView)
        }

        private func syncBrowserState(from webView: WKWebView) {
            Task { @MainActor in
                browserState.currentURL = webView.url?.absoluteString ?? browserState.currentURL
                browserState.pageTitle = webView.title ?? ""
                browserState.isLoading = webView.isLoading
                browserState.canGoBack = webView.canGoBack
                browserState.canGoForward = webView.canGoForward
                browserState.progress = webView.estimatedProgress
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            observe(webView)
            handlerContext?.mark3DInspectorInactive(notify: false)
            documentNavigationStart = Date()
            capturedDocumentResponseURL = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            syncBrowserState(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            syncBrowserState(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            recordMainDocumentResponse(navigationResponse)
            decisionHandler(.allow)
        }

        // MARK: - WKUIDelegate

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Open target=_blank links in same view
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

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
}
