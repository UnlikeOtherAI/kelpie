import Foundation

@MainActor
extension HandlerContext {
    /// Resolves the per-renderer dialog state for the targeted renderer.
    func dialogState(windowId: String?, tabId: String?) throws -> DialogState? {
        let renderer = try resolveRenderer(windowId: windowId, tabId: tabId)
        if let webKit = renderer as? WKWebViewRenderer {
            return webKit.dialogState
        }
        if let chromium = renderer as? CEFRenderer {
            return chromium.dialogState
        }
        return nil
    }

    /// Most recent main-frame navigation error captured by the targeted renderer.
    func navigationError(windowId: String?, tabId: String?) -> String? {
        guard let renderer = try? resolveRenderer(windowId: windowId, tabId: tabId) else { return nil }
        return (renderer as? WKWebViewRenderer)?.lastNavigationError
    }

    /// Legacy single-window form of `navigationError(windowId:tabId:)`.
    func navigationError(tabId: String?) -> String? {
        navigationError(windowId: nil, tabId: tabId)
    }
}
