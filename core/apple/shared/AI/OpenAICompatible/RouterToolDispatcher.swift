import Foundation

/// Runs agent tool calls through Kelpie's own HTTP router so they get the same
/// tab resolution, validation and script-recording gate as API callers.
struct RouterToolDispatcher: OpenAIToolDispatching {
    let router: Router

    func browserSession(tabId: String?, allowActions: Bool) async -> BrowserControlGateway {
        await router.makeBrowserGateway(allowActions: allowActions, pinnedTabId: tabId, agent: true)
    }

    func dispatch(method: String, body: [String: Any]) async -> [String: Any] {
        await router.handle(method: method, body: body).json
    }
}

extension OpenAIToolDispatching {
    func browserSession(tabId: String?, allowActions: Bool) async -> BrowserControlGateway {
        await MainActor.run {
            let methods = OpenAIBrowserToolCatalog.tools(allowActions: allowActions).map(\.routerMethod) + ["get-tabs", "get-current-url", "type"]
            return BrowserControlGateway(
                methods: methods,
                extensions: BrowserControlGateway.extensions(platform: 2, methods: methods),
                targeting: "direct",
                allowActions: allowActions,
                dispatch: { method, params, _ in
                    var params = params
                    if let tabId { params["tabId"] = tabId }
                    return await self.dispatch(method: method, body: params)
                },
                authorize: { request, mutates in
                    let target = request["tabId"] as? String ?? (request["params"] as? [String: Any])?["tabId"] as? String
                    return (!mutates || allowActions) && (target == nil || target == tabId) && (request["params"] as? [String: Any])?["windowId"] == nil
                }
            )
        }
    }
}
