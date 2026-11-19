import WebKit

extension HandlerContext {
    func diagnosticTarget(_ body: [String: Any]) throws -> DiagnosticTarget {
        try Task.checkCancellation()
        if let remoteDocumentGuard, !remoteDocumentGuard() { throw CancellationError() }
        let tabId = body["tabId"] as? String
        let target: WKWebView?
        if let tabId {
            if let store = tabStore {
                target = store.tabs.first { $0.id == UUID(uuidString: tabId) }?.webView
            } else {
                target = tabId == "external" ? webView : nil
            }
            if target == nil { throw DiagnosticError.tabNotFound(tabId) }
        } else {
            target = tabStore?.activeBrowserTab?.webView ?? webView
        }
        guard let target else { throw HandlerError.noWebView }
        return DiagnosticTarget(buffer: BrowserDiagnostics.forTarget(target)) { [weak self] script in
            let result = try await target.evaluateJavaScript(script)
            if self?.remoteDocumentGuard?() == false { throw CancellationError() }
            return result
        }
    }
}
