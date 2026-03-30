import SwiftUI
import WebKit

/// Wraps WKWebView in a UIViewRepresentable for SwiftUI.
struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var browserState: BrowserState
    let onWebView: (WKWebView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(browserState: browserState)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        context.coordinator.webView = webView
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
        weak var webView: WKWebView?
        private var progressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?
        private var backObservation: NSKeyValueObservation?
        private var forwardObservation: NSKeyValueObservation?

        init(browserState: BrowserState) {
            self.browserState = browserState
            super.init()
        }

        func observe(_ webView: WKWebView) {
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
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if progressObservation == nil { observe(webView) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                browserState.isLoading = false
            }
        }

        // MARK: - WKUIDelegate

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Open target=_blank links in same view
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
