import WebKit

struct MobileTabHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("get-tabs") { _ in await getTabs() }
        router.register("new-tab") { body in await newTab(body) }
        router.register("switch-tab") { body in await switchTab(body) }
        router.register("close-tab") { body in await closeTab(body) }
        router.register("get-partitions") { _ in
            successResponse(["partitions": await MobilePartitionRegistry.shared.listing(tabs: context.tabStore?.tabs ?? [])])
        }
        router.register("delete-partition") { body in
            guard let id = body["id"] as? String else { return errorResponse(code: "MISSING_PARAM", message: "id required") }
            guard let tabStore = context.tabStore else { return errorResponse(code: "NO_TAB_STORE", message: "Tab store not available") }
            return await MobilePartitionRegistry.shared.delete(id, tabStore: tabStore)
        }
    }

    // MARK: - Tabs

    @MainActor
    private func tabInfo(_ tab: BrowserTab, tabStore: TabStore) -> [String: Any] {
        var result: [String: Any] = [
            "id": tab.id.uuidString,
            "windowId": "main",
            "url": tab.currentURL,
            "title": tab.pageTitle,
            "active": tab.id == tabStore.activeBrowserTabID,
            "isLoading": tab.isLoading
        ]
        if let name = tab.name { result["name"] = name }
        if let partition = tab.partition { result["partition"] = partition; result["persistent"] = true }
        return result
    }

    @MainActor
    private func getTabs() async -> [String: Any] {
        guard let tabStore = context.tabStore else {
            guard let webView = context.webView else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
            let tab: [String: Any] = [
                "id": "0",
                "windowId": "main",
                "url": webView.url?.absoluteString ?? "",
                "title": webView.title ?? "",
                "active": true,
                "isLoading": false
            ]
            return successResponse(["windowId": "main", "tabs": [tab], "count": 1, "activeTab": "0"])
        }
        let tabs = tabStore.tabs.map { tabInfo($0, tabStore: tabStore) }
        return successResponse([
            "windowId": "main",
            "tabs": tabs,
            "count": tabs.count,
            "activeTab": tabStore.activeBrowserTabID?.uuidString ?? ""
        ])
    }

    @MainActor
    private func newTab(_ body: [String: Any]) async -> [String: Any] {
        guard let tabStore = context.tabStore else {
            return errorResponse(code: "NO_TAB_STORE", message: "Tab store not available")
        }
        let url = body["url"] as? String
        let tab: BrowserTab
        do {
            let options = try MobilePartitionRegistry.validate(body)
            let store = try options.partition.map { try MobilePartitionRegistry.shared.resolve($0) }
                ?? WebViewDefaults.sharedWebsiteDataStore
            tab = tabStore.addBrowserTab(url: url, dataStore: store, partition: options.partition, name: options.name)
        } catch let failure as MobilePartitionRegistry.Failure {
            return failure.response
        } catch { return errorResponse(code: "PARTITION_UNSUPPORTED", message: error.localizedDescription) }
        return successResponse([
            "tabId": tab.id.uuidString,
            "tab": tabInfo(tab, tabStore: tabStore),
            "tabCount": tabStore.tabs.count,
            "windowId": "main"
        ])
    }

    @MainActor
    private func switchTab(_ body: [String: Any]) async -> [String: Any] {
        guard let tabStore = context.tabStore else {
            return errorResponse(code: "NO_TAB_STORE", message: "Tab store not available")
        }
        guard let idString = parseTabID(body), let id = UUID(uuidString: idString) else {
            return errorResponse(code: "MISSING_PARAM", message: "tabId (UUID string) is required")
        }
        guard tabStore.tabs.contains(where: { $0.id == id }) else {
            return errorResponse(code: "TAB_NOT_FOUND", message: "Tab \(idString) not found")
        }
        tabStore.selectBrowserTab(id: id)
        guard let activeTab = tabStore.activeBrowserTab else {
            return errorResponse(code: "SWITCH_FAILED", message: "Tab switch failed")
        }
        return successResponse(["tab": tabInfo(activeTab, tabStore: tabStore), "windowId": "main"])
    }

    @MainActor
    private func closeTab(_ body: [String: Any]) async -> [String: Any] {
        guard let tabStore = context.tabStore else {
            return errorResponse(code: "NO_TAB_STORE", message: "Tab store not available")
        }
        guard let idString = parseTabID(body), let id = UUID(uuidString: idString) else {
            return errorResponse(code: "MISSING_PARAM", message: "tabId (UUID string) is required")
        }
        guard tabStore.tabs.contains(where: { $0.id == id }) else {
            return errorResponse(code: "TAB_NOT_FOUND", message: "Tab \(idString) not found")
        }
        tabStore.closeBrowserTab(id: id)
        return successResponse([
            "closed": idString,
            "tabCount": tabStore.tabs.count,
            "windowId": "main"
        ])
    }

    private func parseTabID(_ body: [String: Any]) -> String? {
        body["tabId"] as? String ?? body["id"] as? String
    }
}
