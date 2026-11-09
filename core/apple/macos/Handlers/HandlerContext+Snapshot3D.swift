import Foundation

extension HandlerContext {
    func enter3DInspector(windowId: String? = nil) async throws {
        let tabId = tabStore(windowId: windowId, tabId: nil)?.activeTab?.id.uuidString
        let snapshot = try? await takeSnapshot(tabId: tabId)
        let payload = if let snapshot {
            try? await screenshotPayload(from: snapshot, format: "png", quality: 1, resolution: .viewport, tabId: tabId)
        } else {
            nil as [String: Any]?
        }
        _ = try await evaluateJS(Snapshot3DBridge.enterScript, windowId: windowId, tabId: tabId)
        if let image = payload?["image"] as? String {
            _ = try? await evaluateJS(Snapshot3DBridge.previewScript(image), windowId: windowId, tabId: tabId)
        }
    }

    /// The inspector follows the visible page, including in windows with several tabs.
    /// General automation still requires an explicit tab when several are open.
    func evaluate3DInspectorJS(_ script: String, windowId: String? = nil) async throws -> Any? {
        let tabId = tabStore(windowId: windowId, tabId: nil)?.activeTab?.id.uuidString
        return try await evaluateJS(script, windowId: windowId, tabId: tabId)
    }
}
