import Foundation

// MARK: - OpenAI-compatible backend dispatch (macOS)
//
// Transport, health and the agent loop live in AI/OpenAICompatible (shared
// with iOS). This file only adapts them to the macOS tab model.

extension AIHandler {
    enum TabPin {
        case pinned(String?)
        case rejected([String: Any])
    }

    func inferWithOpenAI(_ body: [String: Any]) async -> [String: Any] {
        if let rejection = await openAI.preflight(body: body) {
            return rejection
        }
        guard let router else {
            return errorResponse(code: "AI_UNAVAILABLE", message: "The AI router is not initialised.")
        }

        let tabId: String?
        switch await pinTab(requested: HandlerContext.tabId(from: body)) {
        case .pinned(let pinned): tabId = pinned
        case .rejected(let response): return response
        }

        let contextMode = body["context"] as? String
        let explicitText = body["text"] as? String
        let contextText: String?
        if let explicitText {
            contextText = explicitText
        } else {
            if contextMode != nil {
                let gateway = await router.makeBrowserGateway(allowActions: false, pinnedTabId: tabId, agent: true)
                contextText = OpenAIAgentLoop.json(await gateway.request(["version": 1, "method": "tab.snapshot", "tabId": tabId ?? "", "params": [:]]))
            } else { contextText = nil }
        }
        var image: Data?
        if contextMode == "screenshot" {
            do {
                image = try await screenshotData(tabId: tabId)
            } catch {
                return errorResponse(code: "SCREENSHOT_FAILED", message: error.localizedDescription)
            }
        }

        var pinnedBody = body
        if let tabId { pinnedBody["tabId"] = tabId }
        let request = OpenAIInference.Request.make(body: pinnedBody, contextText: contextText, image: image)
        return await openAI.infer(request, dispatcher: RouterToolDispatcher(router: router))
    }

    /// Pins the agent to one tab for the whole run. Explicit ids are kept;
    /// otherwise a single-tab window pins its only tab, and multi-tab windows
    /// keep the existing "tab required" rule so the caller must choose.
    @MainActor
    func pinTab(requested: String?) -> TabPin {
        if context.activeEngineIsChromium {
            guard requested == nil || requested == "chromium" else { return .rejected(errorResponse(code: "TAB_NOT_FOUND", message: "Unknown Chromium tab")) }
            return .pinned("chromium")
        }
        do {
            _ = try context.resolveRenderer(windowId: nil, tabId: requested)
        } catch {
            return .rejected(tabErrorResponse(from: error) ?? errorResponse(code: "NO_WEBVIEW", message: "No browser tab is available."))
        }
        if let requested {
            guard requested == context.tabStore(windowId: nil, tabId: nil)?.activeTab?.id.uuidString else {
                return .rejected(errorResponse(code: "TAB_NOT_ACTIVE", message: "The agent runs in the visible tab"))
            }
            return .pinned(requested)
        }
        return .pinned(context.tabStore(windowId: nil, tabId: nil)?.activeTab?.id.uuidString)
    }
}
