import Foundation

extension HandlerContext {
    func diagnosticTarget(_ body: [String: Any]) throws -> DiagnosticTarget {
        let tabId = Self.tabId(from: body)
        let windowId = Self.windowId(from: body)
        if activeEngineIsChromium, let tabId, tabId != "chromium" {
            throw DiagnosticError.tabNotFound(tabId)
        }
        let selected = tabStore(windowId: windowId, tabId: tabId)?.activeTab?.id.uuidString
        let target = try resolveRenderer(windowId: windowId, tabId: tabId ?? selected)
        return DiagnosticTarget(buffer: BrowserDiagnostics.forTarget(target)) { [weak self] script in
            let result = try await target.evaluateJS(script)
            if self?.remoteDocumentGuard?() == false { throw CancellationError() }
            return result
        }
    }
}
