import Foundation

extension HandlerContext {
    /// The inspector follows the visible page, including in windows with several tabs.
    /// General automation still requires an explicit tab when several are open.
    func evaluate3DInspectorJS(_ script: String, windowId: String? = nil) async throws -> Any? {
        let tabId = tabStore(windowId: windowId, tabId: nil)?.activeTab?.id.uuidString
        return try await evaluateJS(script, windowId: windowId, tabId: tabId)
    }
}
