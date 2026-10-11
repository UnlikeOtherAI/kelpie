import Foundation
import WebKit

extension Router {
    @MainActor
    private var browserProfile: String {
        #if os(iOS)
        return "ios"
        #else
        return handlerContext?.activeEngineIsChromium == true ? "chromium" : "webkit"
        #endif
    }

    @MainActor
    func browserControl(_ body: [String: Any]) async -> [String: Any] {
        await directGateway().request(body)
    }

    @MainActor
    func browserMCP(_ body: [String: Any]) async -> [String: Any] {
        await directGateway().request(body, mcp: true)
    }

    @MainActor
    private func directGateway() -> BrowserControlGateway {
        if let browserGateway, browserGatewayProfile == browserProfile { return browserGateway }
        let gateway = makeBrowserGateway(allowActions: true, pinnedTabId: nil, agent: false)
        browserGateway = gateway
        browserGatewayProfile = browserProfile
        return gateway
    }

    @MainActor
    func makeBrowserGateway(allowActions: Bool, pinnedTabId: String?, agent: Bool) -> BrowserControlGateway {
        #if os(iOS)
        let platform: Int32 = 0
        let targeting = "selected"
        #else
        let platform: Int32 = 2
        let targeting = "direct"
        #endif
        var methods = registeredMethods
        #if os(macOS)
        if browserProfile == "chromium" { methods.removeAll { ["new-tab", "switch-tab", "close-tab"].contains($0) } }
        #endif
        if agent {
            // The agent retains its existing admitted product extensions; scripts,
            // cookies and machine settings are not admitted through discovery.
            let allowed = Set(OpenAIBrowserToolCatalog.tools(allowActions: allowActions).map(\.routerMethod))
            methods = methods.filter { allowed.contains($0) || ["get-tabs", "get-current-url", "type"].contains($0) }
        }
        let extensions = BrowserControlGateway.extensions(platform: platform, methods: methods)
        let profile = browserProfile
        let gateway = BrowserControlGateway(
            methods: methods,
            extensions: extensions,
            targeting: targeting,
            allowActions: allowActions,
            lease: browserLease,
            dispatch: { [weak self] method, params, mutates in
                guard let self, self.browserProfile == profile else { return errorResponse(code: "RENDERER_CHANGED", message: "Renderer changed") }
                if agent && !self.agentTargetAllowed(tabId: pinnedTabId) {
                    return errorResponse(code: "TAB_CHANGED", message: "The pinned tab is no longer visible")
                }
                if mutates { self.invalidateAllBrowserReferences() }
                return await self.browserDispatch(method: method, params: params, pinnedTabId: agent ? pinnedTabId : nil)
            },
            authorize: { [weak self] request, mutates in
                guard let self, self.browserProfile == profile else { return false }
                guard !agent || (self.agentTargetAllowed(tabId: pinnedTabId) && (allowActions || !mutates)) else { return false }
                if agent {
                    let target = request["tabId"] as? String ?? (request["params"] as? [String: Any])?["tabId"] as? String
                    if let target, target != pinnedTabId { return false }
                    let window = (request["params"] as? [String: Any])?["windowId"]
                    if window != nil { return false }
                }
                return true
            }
        )
        browserGateways.removeAll { $0.gateway == nil }
        browserGateways.append(WeakBrowserGateway(gateway))
        return gateway
    }

    @MainActor
    private var selectedBrowserTabId: String? {
        #if os(iOS)
        return handlerContext?.tabStore?.activeBrowserTabID?.uuidString ?? (handlerContext?.webView != nil ? "external" : nil)
        #else
        return handlerContext?.tabStore(windowId: nil, tabId: nil)?.activeTab?.id.uuidString
        #endif
    }

    @MainActor
    private func agentTargetAllowed(tabId: String?) -> Bool {
        #if os(iOS)
        return selectedBrowserTabId == tabId
        #else
        if handlerContext?.activeEngineIsChromium == true { return tabId == "chromium" }
        return handlerContext?.tabStore(windowId: nil, tabId: nil)?.activeTab?.id.uuidString == tabId
        #endif
    }

    @MainActor
    private func browserDispatch(method: String, params: [String: Any], pinnedTabId: String?) async -> [String: Any] {
        var params = params
        if let pinnedTabId { params["tabId"] = pinnedTabId }
        if let target = params["tabId"] as? String, !target.isEmpty {
            #if os(iOS)
            if !["switch-tab", "close-tab", "get-tabs"].contains(method), target != selectedBrowserTabId {
                return errorResponse(code: "TAB_CHANGED", message: "The target tab is no longer visible")
            }
            #else
            if handlerContext?.activeEngineIsChromium == true, target != "chromium" {
                return errorResponse(code: "TAB_NOT_FOUND", message: "Unknown Chromium tab")
            }
            #endif
        }
        #if os(iOS)
        let previousTarget = handlerContext?.browserControlTabId
        handlerContext?.browserControlTabId = params["tabId"] as? String
        defer { handlerContext?.browserControlTabId = previousTarget }
        if let store = handlerContext?.tabStore, store.activeBrowserTab?.webView !== handlerContext?.webView,
           !["get-tabs", "switch-tab", "close-tab", "new-tab"].contains(method) {
            return errorResponse(code: "TAB_CHANGED", message: "The selected renderer has not settled")
        }
        #else
        let previousEngine = handlerContext?.browserControlEngineName
        handlerContext?.browserControlEngineName = handlerContext?.renderer?.engineName
        defer { handlerContext?.browserControlEngineName = previousEngine }
        #endif
        if method == "browser-control-evaluate" {
            guard let expression = params["expression"] as? String, let context = handlerContext else {
                return errorResponse(code: "NO_WEBVIEW", message: "No renderer")
            }
            do {
                #if os(iOS)
                guard params["tabId"] as? String == selectedBrowserTabId,
                      let webView = context.webView else { return errorResponse(code: "TAB_CHANGED", message: "Tab is not active") }
                let result = try await webView.evaluateJavaScript(expression, in: nil, in: .world(name: "KelpieBrowserControl"))
                #else
                let renderer = try context.resolveRenderer(tabId: params["tabId"] as? String)
                let result = try await renderer.evaluateBrowserControlJS(expression)
                #endif
                return successResponse(["result": result ?? NSNull()])
            } catch { return errorResponse(code: "WEBVIEW_ERROR", message: "Fixed browser operation failed") }
        }
        if method == "get-tabs" {
            #if os(iOS)
            if let context = handlerContext, context.tabStore == nil, let webView = context.webView {
                return successResponse(["activeTab": "external", "tabs": [["id": "external", "active": true, "url": webView.url?.absoluteString ?? "", "title": webView.title ?? ""]]])
            }
            #endif
            #if os(macOS)
            if let context = handlerContext, context.activeEngineIsChromium {
                return successResponse(["activeTab": "chromium", "tabs": [[
                    "id": "chromium", "active": true, "url": context.renderer?.currentURL?.absoluteString ?? "",
                    "title": context.renderer?.currentTitle ?? ""
                ]]])
            }
            #endif
            var result = await handle(method: method, body: params, browserGatewayDispatch: true).json
            if let windows = result["windows"] as? [[String: Any]] {
                result["tabs"] = windows.flatMap { $0["tabs"] as? [[String: Any]] ?? [] }
            }
            if let pinnedTabId, let tabs = result["tabs"] as? [[String: Any]] {
                result["tabs"] = tabs.filter { $0["id"] as? String == pinnedTabId }
                result["activeTab"] = pinnedTabId
            }
            return result
        }
        return await handle(method: method, body: params, browserGatewayDispatch: true).json
    }

    @MainActor
    func invalidateAllBrowserReferences() {
        for entry in browserGateways { entry.gateway?.invalidate() }
    }

    @MainActor
    func isBrowserMutation(method: String) -> Bool {
        // AI inference recursively uses the gateway; it is not itself a browser gesture.
        guard !method.hasPrefix("ai-"), method != "infer" else { return false }
        return directGateway().invalidates(method: method)
    }

    @MainActor
    func invalidateBrowserReferences(method: String, body: [String: Any]) {
        for entry in browserGateways where entry.gateway?.invalidates(method: method) == true {
            entry.gateway?.invalidate(tabId: body["tabId"] as? String)
        }
    }
}
