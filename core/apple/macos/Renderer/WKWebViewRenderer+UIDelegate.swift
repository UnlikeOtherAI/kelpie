import AppKit
import WebKit

extension WKWebViewRenderer: WKUIDelegate {
    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        guard let window = webView.window, window.attachedSheet == nil,
              !webView.isHiddenOrHasHiddenAncestor else {
            completionHandler(nil)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = !parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        // WebKit loads the original request in the returned view and links
        // the native browsing contexts, including a window.open() handle.
        return onOpenWindow?(configuration, windowFeatures)
    }

    func webViewDidClose(_ webView: WKWebView) { onClose?() }

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
}
