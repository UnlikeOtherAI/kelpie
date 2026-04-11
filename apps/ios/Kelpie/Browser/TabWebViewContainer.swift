import SwiftUI
import WebKit

enum ScrollDirection {
    case up, down
}

/// Displays the active tab's WKWebView, handles navigation/UI delegation,
/// and tracks scroll direction for bottom-bar collapse/expand.
struct TabWebViewContainer: UIViewRepresentable {
    @ObservedObject var tabStore: TabStore
    @ObservedObject var browserState: BrowserState
    let handlerContext: HandlerContext?
    let onScrollDirectionChange: (ScrollDirection) -> Void
    let onWebViewReady: (WKWebView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            browserState: browserState,
            handlerContext: handlerContext,
            onScrollDirectionChange: onScrollDirectionChange,
            onWebViewReady: onWebViewReady
        )
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        if let webView = tabStore.activeBrowserTab?.webView {
            context.coordinator.install(webView: webView, in: container)
        }
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let webView = tabStore.activeBrowserTab?.webView else { return }
        context.coordinator.install(webView: webView, in: container)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let browserState: BrowserState
        weak var handlerContext: HandlerContext?
        let onScrollDirectionChange: (ScrollDirection) -> Void
        let onWebViewReady: (WKWebView) -> Void

        weak var currentWebView: WKWebView?
        private var progressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?
        private var backObservation: NSKeyValueObservation?
        private var forwardObservation: NSKeyValueObservation?
        private var contentOffsetObservation: NSKeyValueObservation?
        private var documentNavigationStart: Date?
        private var capturedDocumentResponseURL: String?
        private var lastScrollOffset: CGFloat = 0

        init(
            browserState: BrowserState,
            handlerContext: HandlerContext?,
            onScrollDirectionChange: @escaping (ScrollDirection) -> Void,
            onWebViewReady: @escaping (WKWebView) -> Void
        ) {
            self.browserState = browserState
            self.handlerContext = handlerContext
            self.onScrollDirectionChange = onScrollDirectionChange
            self.onWebViewReady = onWebViewReady
            super.init()
        }

        func install(webView: WKWebView, in container: UIView) {
            guard webView !== currentWebView else { return }

            currentWebView?.removeFromSuperview()
            clearObservations()

            webView.frame = container.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView.navigationDelegate = self
            webView.uiDelegate = self
            container.addSubview(webView)

            currentWebView = webView
            lastScrollOffset = webView.scrollView.contentOffset.y
            observe(webView)
            syncBrowserState(from: webView)
            onWebViewReady(webView)
        }

        private func clearObservations() {
            progressObservation = nil
            titleObservation = nil
            urlObservation = nil
            loadingObservation = nil
            backObservation = nil
            forwardObservation = nil
            contentOffsetObservation = nil
        }

        private func observe(_ webView: WKWebView) {
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
            contentOffsetObservation = webView.scrollView.observe(\.contentOffset) { [weak self] scrollView, _ in
                guard let self else { return }
                let offset = scrollView.contentOffset.y
                let delta = offset - self.lastScrollOffset
                if offset <= 0 {
                    self.onScrollDirectionChange(.up)
                } else if delta > 12 {
                    self.onScrollDirectionChange(.down)
                    self.lastScrollOffset = offset
                } else if delta < -12 {
                    self.onScrollDirectionChange(.up)
                    self.lastScrollOffset = offset
                }
            }
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

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
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

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            guard let dialogState = handlerContext?.dialogState else {
                completionHandler()
                return
            }
            dialogState.enqueue(
                DialogState.PendingDialog(type: .alert, message: message, defaultText: nil) { _ in
                    completionHandler()
                }
            )
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            guard let dialogState = handlerContext?.dialogState else {
                completionHandler(false)
                return
            }
            dialogState.enqueue(
                DialogState.PendingDialog(type: .confirm, message: message, defaultText: nil) { result in
                    completionHandler(result != nil)
                }
            )
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            guard let dialogState = handlerContext?.dialogState else {
                completionHandler(nil)
                return
            }
            dialogState.enqueue(
                DialogState.PendingDialog(type: .prompt, message: prompt, defaultText: defaultText) { result in
                    completionHandler(result)
                }
            )
        }

        // MARK: - Network Recording

        private func recordMainDocumentResponse(_ response: WKNavigationResponse) {
            guard response.isForMainFrame,
                  let http = response.response as? HTTPURLResponse,
                  let url = http.url?.absoluteString,
                  capturedDocumentResponseURL != url else {
                return
            }

            let contentType = http.mimeType
                ?? http.value(forHTTPHeaderField: "Content-Type")
                ?? "text/html"
            let size = Int(http.expectedContentLength)
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { dict, item in
                dict[String(describing: item.key)] = String(describing: item.value)
            }

            NetworkTrafficStore.shared.appendDocumentNavigation(
                url: url,
                statusCode: http.statusCode,
                contentType: contentType,
                responseHeaders: headers,
                size: size > 0 ? size : 0,
                startedAt: documentNavigationStart ?? Date()
            )

            capturedDocumentResponseURL = url
        }
    }
}
