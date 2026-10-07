import Foundation

// MARK: - OpenAI-compatible backend dispatch (iOS)
//
// Transport, health and the agent loop live in the shared
// apps/macos/Kelpie/AI/OpenAICompatible sources. This file only adapts them to
// the iOS tab model: every iOS handler acts on the visible tab's WebView, so
// the agent is pinned to the tab that is visible when the run starts.

extension AIHandler {
    static let openAIHost = OpenAIEndpointHandler.Host(
        platform: "ios",
        loopbackMeans: "localhost, 127.0.0.1 and [::1] mean this iPhone or iPad — the device running Kelpie — not your computer. "
            + "To use a server on your computer, enter its LAN or .local address and make sure that server listens on the network."
    )

    enum TabPin {
        case pinned(String?)
        case rejected([String: Any])
    }

    /// `ai-load {backend: "openai"}`. Failure leaves the current backend as it was.
    func loadOpenAI(_ body: [String: Any]) async -> [String: Any] {
        let response = await openAI.load(body)
        guard response["success"] as? Bool == true, let model = response["model"] as? String else {
            return response
        }
        let capabilities = response["capabilities"] as? [String] ?? ["text"]
        await MainActor.run {
            AIState.shared.activateOpenAI(model: model, capabilities: capabilities)
        }
        return response
    }

    func inferWithOpenAI(_ body: [String: Any]) async -> [String: Any] {
        if let rejection = await openAI.preflight(body: body) {
            return rejection
        }
        guard let router else {
            return errorResponse(code: "AI_UNAVAILABLE", message: "The AI router is not initialised.")
        }

        let tabId: String?
        switch await pinTab(requested: body["tabId"] as? String) {
        case .pinned(let pinned): tabId = pinned
        case .rejected(let response): return response
        }

        let contextMode = body["context"] as? String
        let contextText: String?
        if let explicitText = body["text"] as? String {
            contextText = explicitText
        } else {
            contextText = await preloadedContext(mode: contextMode, router: router)
        }
        var image: Data?
        if contextMode == "screenshot" {
            // Preflight already refused screenshots unless the model has vision.
            switch await screenshot(router: router) {
            case .image(let data): image = data
            case .failed(let response): return response
            }
        }

        var pinnedBody = body
        if let tabId { pinnedBody["tabId"] = tabId }
        let request = OpenAIInference.Request.make(body: pinnedBody, contextText: contextText, image: image)
        let dispatcher = VisibleTabToolDispatcher(
            base: RouterToolDispatcher(router: router),
            pinnedTabId: tabId,
            visibleTabId: { [context] in await MainActor.run { context.tabStore?.activeBrowserTabID?.uuidString } }
        )
        return await openAI.infer(request, dispatcher: dispatcher)
    }

    /// Pins the run to one tab. iOS handlers act on the visible tab, so an
    /// explicit `tabId` must name the visible tab; otherwise the visible tab
    /// is pinned.
    @MainActor
    func pinTab(requested: String?) -> TabPin {
        guard context.webView != nil else {
            return .rejected(errorResponse(code: "NO_WEBVIEW", message: "No browser tab is available."))
        }
        guard let tabStore = context.tabStore else { return .pinned(requested) }
        guard let requested else { return .pinned(tabStore.activeBrowserTabID?.uuidString) }
        guard let id = UUID(uuidString: requested), tabStore.tabs.contains(where: { $0.id == id }) else {
            return .rejected(errorResponse(code: "TAB_NOT_FOUND", message: "Tab \(requested) not found"))
        }
        guard id == tabStore.activeBrowserTabID else {
            return .rejected(errorResponse(
                code: "TAB_NOT_ACTIVE",
                message: "On iOS the agent runs in the visible tab. Switch to tab \(requested) with switch-tab first."
            ))
        }
        return .pinned(requested)
    }

    /// Page data for `context: page_text | dom | accessibility`, gathered with
    /// the same router methods API callers use.
    func preloadedContext(mode: String?, router: Router) async -> String? {
        let request: (method: String, body: [String: Any])
        switch mode {
        case "page_text": request = ("get-page-text", [:])
        case "dom": request = ("get-dom", ["selector": "body"])
        case "accessibility": request = ("get-accessibility-tree", ["maxDepth": 3])
        default: return nil
        }
        var result = await router.handle(method: request.method, body: request.body).json
        guard result["success"] as? Bool == true else { return "" }
        result.removeValue(forKey: "success")
        return OpenAIAgentLoop.json(result)
    }

    enum ScreenshotOutcome {
        case image(Data)
        case failed([String: Any])
    }

    func screenshot(router: Router) async -> ScreenshotOutcome {
        let result = await router.handle(method: "screenshot", body: ["format": "png", "resolution": "viewport"]).json
        guard result["success"] as? Bool == true,
              let encoded = result["image"] as? String,
              let data = Data(base64Encoded: encoded) else {
            let message = (result["error"] as? [String: Any])?["message"] as? String ?? "Failed to capture the page."
            return .failed(errorResponse(code: "SCREENSHOT_FAILED", message: message))
        }
        return .image(data)
    }
}

/// Refuses agent tool calls once the pinned tab is no longer the visible one,
/// so a run never silently continues in a tab the user switched to.
struct VisibleTabToolDispatcher: OpenAIToolDispatching {
    let base: OpenAIToolDispatching
    let pinnedTabId: String?
    let visibleTabId: @Sendable () async -> String?

    func dispatch(method: String, body: [String: Any]) async -> [String: Any] {
        if let pinnedTabId, await visibleTabId() != pinnedTabId {
            return errorResponse(
                code: "TAB_CHANGED",
                message: "The tab this run is pinned to is no longer visible; Kelpie on iOS only acts on the visible tab."
            )
        }
        return await base.dispatch(method: method, body: body)
    }
}
