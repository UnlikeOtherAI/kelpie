import Foundation

/// Tab lifecycle endpoints for `BrowserManagementHandler`.
///
/// Split out of the main handler so the partition fields on `new-tab` had
/// somewhere to live without pushing that file past the 500-line limit. Tab
/// management is WebKit-only throughout: CEF models a single browser, so every
/// endpoint here refuses while Chromium is active.
extension BrowserManagementHandler {
    // MARK: - Tabs

    @MainActor
    func getTabs(_ body: [String: Any]) async -> [String: Any] {
        if context.renderer?.engineName == "chromium" {
            return context.cefUnsupportedError(feature: "Tab management")
        }
        let requestedWindowId = HandlerContext.windowId(from: body)

        // Multi-window listing: when no windowId is supplied, return every
        // window's tabs so LLMs can discover which `windowId` to target.
        if requestedWindowId == nil {
            let entries = WindowRegistry.shared.allEntries()
            if entries.count > 1 {
                let windows = entries.map { entry -> [String: Any] in
                    let tabs = entry.tabStore.tabs.map { tab in
                        tabInfoPayload(for: tab, activeID: entry.tabStore.activeTabID, windowId: entry.id)
                    }
                    return [
                        "windowId": entry.id,
                        "tabs": tabs,
                        "count": tabs.count,
                        "activeTab": entry.tabStore.activeTabID?.uuidString ?? ""
                    ]
                }
                return successResponse(["windows": windows])
            }
        }

        guard let entry = WindowRegistry.shared.resolveEntry(windowId: requestedWindowId, tabId: nil) else {
            return errorResponse(
                code: "WINDOW_NOT_FOUND",
                message: "No window with id \"\(requestedWindowId ?? "")\""
            )
        }
        let store = entry.tabStore
        let tabs: [[String: Any]] = store.tabs.map { tab in
            tabInfoPayload(for: tab, activeID: store.activeTabID, windowId: entry.id)
        }
        return successResponse([
            "windowId": entry.id,
            "tabs": tabs,
            "count": tabs.count,
            "activeTab": store.activeTabID?.uuidString ?? ""
        ])
    }

    @MainActor
    func tabInfoPayload(for tab: Tab, activeID: UUID?, windowId: String) -> [String: Any] {
        var payload: [String: Any] = [
            "id": tab.id.uuidString,
            "windowId": windowId,
            "url": tab.currentURL,
            "title": tab.title,
            "active": tab.id == activeID,
            "isLoading": tab.isLoading
        ]
        // Omitted rather than sent as null when unset, so existing consumers see
        // a byte-identical payload for an unnamed, unpartitioned tab.
        if let name = tab.name, !name.isEmpty {
            payload["name"] = name
        }
        if let partition = tab.partition {
            payload["partition"] = partition
            payload["persistent"] = tab.persistent
        }
        return payload
    }

    /// A resolved tab spec, or the wire error that stopped it being built.
    ///
    /// Not `Result`: the failure case carries a ready-made JSON response
    /// dictionary, and `Result` requires its failure type to conform to
    /// `Error`, which `[String: Any]` does not.
    enum TabSpecOutcome {
        case resolved(TabSpec)
        case failed([String: Any])
    }

    /// Reads `name`, `partition`, and `persistent` off the request and resolves
    /// the partition to a data store, or returns the wire error for the first
    /// problem found. Resolution happens before the tab is created so a bad
    /// partition never leaves a half-built tab behind.
    @MainActor
    func tabSpec(from body: [String: Any]) -> TabSpecOutcome {
        let name = body["name"] as? String
        if let name, name.count > PartitionValidator.maxNameLength {
            return .failed(errorResponse(
                code: "INVALID_PARAMS",
                message: "name must be at most \(PartitionValidator.maxNameLength) characters"
            ))
        }

        var spec = TabSpec(name: name)
        let requestedPersistent = body["persistent"] as? Bool ?? true
        guard let partition = body["partition"] as? String else {
            guard requestedPersistent else {
                return .failed(errorResponse(
                    code: "INVALID_PARAMS",
                    message: "persistent: false is only meaningful alongside a partition"
                ))
            }
            return .resolved(spec)
        }

        do {
            let resolved = try PartitionRegistry.shared.resolve(id: partition, persistent: requestedPersistent)
            spec.partition = resolved.id
            spec.persistent = resolved.persistent
            spec.dataStore = resolved.dataStore
            return .resolved(spec)
        } catch let failure as PartitionRegistry.ResolveFailure {
            return .failed(Self.partitionResolveError(failure, id: partition))
        } catch {
            return .failed(errorResponse(code: "INVALID_PARTITION", message: error.localizedDescription))
        }
    }

    @MainActor
    func newTab(_ body: [String: Any]) async -> [String: Any] {
        if context.renderer?.engineName == "chromium" {
            // A partition request gets the discriminating error so the caller
            // knows the engine is the problem; a plain new-tab keeps the
            // existing tab-management message.
            if body["partition"] != nil, let unsupported = chromiumUnsupportedIfActive() {
                return unsupported
            }
            return context.cefUnsupportedError(feature: "Tab management")
        }
        let spec: TabSpec
        switch tabSpec(from: body) {
        case .resolved(let value): spec = value
        case .failed(let error): return error
        }
        let requestedWindowId = HandlerContext.windowId(from: body)
        guard let entry = WindowRegistry.shared.resolveEntry(windowId: requestedWindowId, tabId: nil),
              let callbacks = entry.callbacks else {
            return errorResponse(
                code: requestedWindowId == nil ? "NO_TAB_STORE" : "WINDOW_NOT_FOUND",
                message: requestedWindowId == nil
                    ? "Tab store not initialised"
                    : "No window with id \"\(requestedWindowId ?? "")\""
            )
        }
        let tab = callbacks.onNewTab(spec)
        if let urlString = body["url"] as? String,
           let url = URL(string: urlString) {
            // Clear the Start Page overlay so the loaded page is visible —
            // without this the renderer stays hidden behind the blank Start
            // Page even though the navigation succeeds (matches `onWillLoad`).
            tab.isStartPage = false
            tab.currentURL = url.absoluteString
            tab.renderer.load(url: url)
        }
        return successResponse([
            "tabId": tab.id.uuidString,
            "tab": tabInfoPayload(for: tab, activeID: entry.tabStore.activeTabID, windowId: entry.id),
            "tabCount": entry.tabStore.tabs.count,
            "windowId": entry.id
        ])
    }

    @MainActor
    func switchTab(_ body: [String: Any]) async -> [String: Any] {
        if context.renderer?.engineName == "chromium" {
            return context.cefUnsupportedError(feature: "Tab switching")
        }
        guard let tabIdStr = body["tabId"] as? String,
              let tabId = UUID(uuidString: tabIdStr) else {
            return errorResponse(code: "MISSING_PARAM", message: "tabId (UUID string) required")
        }
        let requestedWindowId = HandlerContext.windowId(from: body)
        guard let entry = WindowRegistry.shared.resolveEntry(windowId: requestedWindowId, tabId: tabIdStr),
              let callbacks = entry.callbacks else {
            return errorResponse(
                code: requestedWindowId == nil ? "TAB_NOT_FOUND" : "WINDOW_NOT_FOUND",
                message: requestedWindowId == nil
                    ? "No tab with id \(tabIdStr)"
                    : "No window with id \"\(requestedWindowId ?? "")\""
            )
        }
        guard entry.tabStore.tabs.contains(where: { $0.id == tabId }) else {
            return errorResponse(code: "TAB_NOT_FOUND", message: "No tab with id \(tabIdStr)")
        }
        callbacks.onSwitchTab(tabId)
        guard let tab = entry.tabStore.activeTab else {
            return errorResponse(code: "SWITCH_FAILED", message: "Tab switch failed")
        }
        return successResponse([
            "tab": tabInfoPayload(for: tab, activeID: entry.tabStore.activeTabID, windowId: entry.id),
            "windowId": entry.id
        ])
    }

    @MainActor
    func closeTab(_ body: [String: Any]) async -> [String: Any] {
        if context.renderer?.engineName == "chromium" {
            return context.cefUnsupportedError(feature: "Tab management")
        }
        guard let tabIdStr = body["tabId"] as? String,
              let tabId = UUID(uuidString: tabIdStr) else {
            return errorResponse(code: "MISSING_PARAM", message: "tabId (UUID string) required")
        }
        let requestedWindowId = HandlerContext.windowId(from: body)
        guard let entry = WindowRegistry.shared.resolveEntry(windowId: requestedWindowId, tabId: tabIdStr),
              let callbacks = entry.callbacks else {
            return errorResponse(
                code: requestedWindowId == nil ? "TAB_NOT_FOUND" : "WINDOW_NOT_FOUND",
                message: requestedWindowId == nil
                    ? "No tab with id \(tabIdStr)"
                    : "No window with id \"\(requestedWindowId ?? "")\""
            )
        }
        guard entry.tabStore.tabs.contains(where: { $0.id == tabId }) else {
            return errorResponse(code: "TAB_NOT_FOUND", message: "No tab with id \(tabIdStr)")
        }
        callbacks.onCloseTab(tabId)
        return successResponse([
            "closed": tabIdStr,
            "tabCount": entry.tabStore.tabs.count,
            "windowId": entry.id
        ])
    }
}
