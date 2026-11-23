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
    var bottomClearance: CGFloat = 0
    /// CSS viewport insets with the bottom bar collapsed and expanded.
    var bottomViewportInsets: ClosedRange<CGFloat> = 0...0
    let onScrollDirectionChange: (ScrollDirection) -> Void
    let onWebViewReady: (WKWebView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            tabStore: tabStore,
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
        if webView.scrollView.contentInset.bottom != bottomClearance {
            webView.scrollView.contentInset.bottom = bottomClearance
            webView.scrollView.verticalScrollIndicatorInsets.bottom = bottomClearance
            webView.setMinimumViewportInset(
                UIEdgeInsets(top: 0, left: 0, bottom: bottomViewportInsets.lowerBound, right: 0),
                maximumViewportInset: UIEdgeInsets(top: 0, left: 0, bottom: bottomViewportInsets.upperBound, right: 0)
            )
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var tabStore: TabStore?
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
        private var documentNavigationStart: Date?
        private var capturedDocumentResponseURL: String?
        private var chromeScroll = BrowserChromeScroll()

        init(
            tabStore: TabStore,
            browserState: BrowserState,
            handlerContext: HandlerContext?,
            onScrollDirectionChange: @escaping (ScrollDirection) -> Void,
            onWebViewReady: @escaping (WKWebView) -> Void
        ) {
            self.tabStore = tabStore
            self.browserState = browserState
            self.handlerContext = handlerContext
            self.onScrollDirectionChange = onScrollDirectionChange
            self.onWebViewReady = onWebViewReady
            super.init()
        }

        func install(webView: WKWebView, in container: UIView) {
            guard webView !== currentWebView else { return }

            let retiring = currentWebView
            clearObservations()
            retiring?.navigationDelegate = nil
            retiring?.uiDelegate = nil

            webView.frame = container.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView.scrollView.delaysContentTouches = false
            webView.navigationDelegate = self
            webView.uiDelegate = self
            ExternalAppPrompt.trackUserInput(on: webView)
            container.addSubview(webView)

            currentWebView = webView
            NotificationCenter.default.post(name: .kelpieBrowserDocumentChanged, object: nil)
            chromeScroll = BrowserChromeScroll()
            observe(webView)
            syncBrowserState(from: webView)
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView, webView === self.currentWebView else { return }
                self.onWebViewReady(webView)
            }

            // Defer removal to after the current event cycle so any in-flight
            // UIGestureRecognizer state on the retiring view is fully drained
            // before UIKit releases the view from the hierarchy.
            DispatchQueue.main.async { [weak self, weak retiring, weak container] in
                guard let retiring, retiring !== self?.currentWebView, retiring.superview === container else { return }
                retiring.removeFromSuperview()
            }
        }

        private func clearObservations() {
            progressObservation = nil
            titleObservation = nil
            urlObservation = nil
            loadingObservation = nil
            backObservation = nil
            forwardObservation = nil
            currentWebView?.scrollView.panGestureRecognizer.removeTarget(self, action: #selector(trackUserScroll(_:)))
        }

        private func observe(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress) { [weak self] wv, _ in
                Task { @MainActor in
                    guard let self, wv === self.currentWebView else { return }
                    self.browserState.progress = wv.estimatedProgress
                }
            }
            titleObservation = webView.observe(\.title) { [weak self] wv, _ in
                Task { @MainActor in
                    guard let self, wv === self.currentWebView else { return }
                    self.browserState.pageTitle = wv.title ?? ""
                }
            }
            urlObservation = webView.observe(\.url) { [weak self] wv, _ in
                Task { @MainActor in
                    guard let self, wv === self.currentWebView else { return }
                    self.browserState.currentURL = wv.url?.absoluteString ?? ""
                }
            }
            loadingObservation = webView.observe(\.isLoading) { [weak self] wv, _ in
                Task { @MainActor in
                    guard let self, wv === self.currentWebView else { return }
                    self.browserState.isLoading = wv.isLoading
                }
            }
            backObservation = webView.observe(\.canGoBack) { [weak self] wv, _ in
                Task { @MainActor in
                    guard let self, wv === self.currentWebView else { return }
                    self.browserState.canGoBack = wv.canGoBack
                }
            }
            forwardObservation = webView.observe(\.canGoForward) { [weak self] wv, _ in
                Task { @MainActor in
                    guard let self, wv === self.currentWebView else { return }
                    self.browserState.canGoForward = wv.canGoForward
                }
            }
            webView.scrollView.panGestureRecognizer.addTarget(self, action: #selector(trackUserScroll(_:)))
        }

        @objc private func trackUserScroll(_ pan: UIPanGestureRecognizer) {
            guard let scrollView = currentWebView?.scrollView, pan === scrollView.panGestureRecognizer else { return }
            if pan.state == .began { chromeScroll = BrowserChromeScroll() }
            guard pan.state == .began || pan.state == .changed else { return }
            let inset = scrollView.adjustedContentInset
            let direction = chromeScroll.update(
                translation: -pan.translation(in: scrollView).y,
                offset: scrollView.contentOffset.y + inset.top,
                maximum: max(0, scrollView.contentSize.height - scrollView.bounds.height + inset.top + inset.bottom),
                userDragging: true
            )
            if let direction { onScrollDirectionChange(direction) }
        }

        private func syncBrowserState(from webView: WKWebView) {
            Task { @MainActor in
                guard webView === currentWebView else { return }
                browserState.currentURL = webView.url?.absoluteString ?? ""
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
            ConnectDocument.navigated(webView, navigation: navigation)
            guard webView === currentWebView else { return }
            chromeScroll = BrowserChromeScroll()
            // Each new provisional navigation starts clean — clear any error captured
            // by a superseded load so a cancelled-then-successful sequence is not fatal.
            let diagnostics = BrowserDiagnostics.forTarget(webView)
            diagnostics.navigationError = nil
            handlerContext?.mark3DInspectorInactive(notify: false)
            documentNavigationStart = Date()
            capturedDocumentResponseURL = nil
            diagnostics.documentResponse = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            syncBrowserState(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            ExternalAppAllowance.of(webView).documentCommitted()
            syncBrowserState(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard webView === currentWebView else { return }
            recordNavigationError(error, in: webView)
            syncBrowserState(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            guard webView === currentWebView else { return }
            recordNavigationError(error, in: webView)
            syncBrowserState(from: webView)
        }

        /// Records a navigation error, ignoring benign cancellations. WKWebView reports
        /// `NSURLErrorCancelled` (-999) on superseded or duplicate loads, http→https
        /// upgrades, and interrupting redirects — none of which are real load failures.
        private func recordNavigationError(_ error: Error, in webView: WKWebView) {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled {
                return
            }
            BrowserDiagnostics.forTarget(webView).navigationError = NavigationFailure.message(for: ns)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            guard webView === currentWebView else { decisionHandler(.allow); return }
            recordMainDocumentResponse(navigationResponse, in: webView)
            let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
            decisionHandler(DownloadPolicy.shouldDownload(
                canShowMIMEType: navigationResponse.canShowMIMEType,
                contentDisposition: disposition
            ) ? .download : .allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            ExternalAppPrompt.decide(navigationAction, in: webView, decisionHandler: decisionHandler)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            DownloadStore.shared.track(download, tabId: nil, origin: .page)
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            DownloadStore.shared.track(download, tabId: nil, origin: .page)
        }

        // MARK: - WKUIDelegate

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            let openTab = pageTabOpener(partition: tabStore?.tabs.first { $0.webView === webView }?.partition)
            switch WebKitWindowPolicy.placement(for: windowFeatures) {
            case .popup:
                return WKPopupViewController.present(from: webView, configuration: configuration, openTab: openTab)
            case .tab:
                return openTab(configuration)
            }
        }

        func webViewDidClose(_ webView: WKWebView) {
            tabStore?.closeBrowserTab(hosting: webView)
        }

        /// Opens tabs for the root tab's pages and pop-ups, in its partition.
        private func pageTabOpener(partition: String?) -> (WKWebViewConfiguration) -> WKWebView? {
            { [weak self] configuration in
                guard let self, let tabStore = self.tabStore else { return nil }
                let webView = tabStore.openPageTab(configuration: configuration, partition: partition)
                // WebKit starts loading into the view at once, before the
                // container installs it, so its policies must already apply.
                webView.navigationDelegate = self
                webView.uiDelegate = self
                return webView
            }
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

        private func recordMainDocumentResponse(_ response: WKNavigationResponse, in webView: WKWebView) {
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

            BrowserDiagnostics.forTarget(webView).documentResponse = (url, http.statusCode, contentType)
            capturedDocumentResponseURL = url
        }
    }
}
