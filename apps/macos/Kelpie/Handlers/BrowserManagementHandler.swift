import AppKit
import WebKit

// swiftlint:disable line_length

/// Handles cookies, storage, clipboard, dialogs, viewport, and unsupported endpoints.
struct BrowserManagementHandler {
    let context: HandlerContext
    let viewportState: ViewportState

    func register(on router: Router) {
        // Unsupported — register stubs FIRST from the single source of truth
        // in `DeviceHandler.unsupportedMethods`. Dedicated handlers below
        // overwrite specific entries (e.g. `is-element-obscured`) where macOS
        // has a real implementation despite the capability list saying
        // otherwise.
        for method in DeviceHandler.unsupportedMethods {
            router.register(method) { _ in
                errorResponse(code: "PLATFORM_NOT_SUPPORTED", message: "\(method) is not supported on macOS")
            }
        }

        // Cookies
        router.register("get-cookies") { body in await getCookies(body) }
        router.register("set-cookie") { body in await setCookie(body) }
        router.register("delete-cookies") { body in await deleteCookies(body) }

        // Storage
        router.register("get-storage") { body in await getStorage(body) }
        router.register("set-storage") { body in await setStorage(body) }
        router.register("clear-storage") { body in await clearStorage(body) }

        // Clipboard
        router.register("get-clipboard") { _ in await getClipboard() }
        router.register("set-clipboard") { body in await setClipboard(body) }

        // Viewport / Fullscreen
        router.register("set-fullscreen") { body in await setFullscreen(body) }
        router.register("get-fullscreen") { body in await getFullscreen(body) }
        router.register("resize-viewport") { body in await resizeViewport(body) }
        router.register("reset-viewport") { body in await resetViewport(body) }
        router.register("set-viewport-preset") { body in await setViewportPreset(body) }
        router.register("is-element-obscured") { body in await isElementObscured(body) }

        // Iframes
        router.register("get-iframes") { body in await getIframes(body) }
        router.register("switch-to-iframe") { body in await switchToIframe(body) }
        router.register("switch-to-main") { _ in successResponse(["context": "main"]) }
        router.register("get-iframe-context") { _ in successResponse(["context": "main"]) }

        // Dialogs
        router.register("get-dialog") { _ in successResponse(["showing": false, "dialog": NSNull()]) }
        router.register("handle-dialog") { body in
            successResponse(["action": body["action"] ?? "accept", "dialogType": "none"])
        }
        router.register("set-dialog-auto-handler") { body in
            successResponse(["enabled": body["enabled"] ?? true])
        }

        // Tabs
        router.register("get-tabs") { _ in await getTabs() }
        router.register("new-tab") { body in await newTab(body) }
        router.register("switch-tab") { body in await switchTab(body) }
        router.register("close-tab") { body in await closeTab(body) }
    }

    // MARK: - Cookies

    @MainActor
    private func getCookies(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        do {
            let renderer = try context.resolveRenderer(tabId: tabId)
            let cookies: [HTTPCookie]
            if tabId == nil {
                cookies = await context.allCookies()
            } else {
                cookies = await renderer.allCookies()
            }
            let name = body["name"] as? String
            let filtered = name != nil ? cookies.filter { $0.name == name } : cookies
            let cookieList = filtered.map { cookie -> [String: Any] in
                ["name": cookie.name, "value": cookie.value, "domain": cookie.domain, "path": cookie.path,
                 "expires": cookie.expiresDate?.description ?? NSNull(), "httpOnly": cookie.isHTTPOnly,
                 "secure": cookie.isSecure, "sameSite": cookie.sameSitePolicy?.rawValue ?? ""]
            }
            return successResponse(["cookies": cookieList, "count": cookieList.count])
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
    }

    @MainActor
    private func setCookie(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        guard let name = body["name"] as? String,
              let value = body["value"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "name and value required")
        }
        do {
            let renderer = try context.resolveRenderer(tabId: tabId)
            var props: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .path: body["path"] as? String ?? "/"]
            if let domain = body["domain"] as? String {
                props[.domain] = domain
            } else {
                props[.domain] = renderer.currentURL?.host ?? "localhost"
            }
            if let cookie = HTTPCookie(properties: props) {
                if tabId == nil {
                    await context.setCookie(cookie)
                } else {
                    await renderer.setCookies([cookie])
                }
                return successResponse()
            }
            return errorResponse(code: "COOKIE_ERROR", message: "Failed to create cookie")
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
    }

    @MainActor
    private func deleteCookies(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        do {
            let renderer = try context.resolveRenderer(tabId: tabId)
            let all = await renderer.allCookies()
            let deleteAll = body["deleteAll"] as? Bool ?? false
            let name = body["name"] as? String
            var deleted = 0
            if deleteAll {
                deleted = all.count
                if tabId == nil {
                    await context.deleteAllCookies()
                } else {
                    await renderer.deleteAllCookies()
                }
                return successResponse(["deleted": deleted])
            }
            for cookie in all where cookie.name == name {
                if tabId == nil {
                    await context.deleteCookie(cookie)
                } else {
                    await renderer.deleteCookie(cookie)
                }
                deleted += 1
            }
            return successResponse(["deleted": deleted])
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
    }

    // MARK: - Storage

    @MainActor
    private func getStorage(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        let type = body["type"] as? String ?? "local"
        let key = body["key"] as? String
        let storage = type == "session" ? "sessionStorage" : "localStorage"
        let escapedType = JSEscape.string(type)
        let js: String
        if let key {
            let escapedKey = JSEscape.string(key)
            js = "({entries: {'\(escapedKey)': \(storage).getItem('\(escapedKey)') || ''}, count: 1, type: '\(escapedType)'})"
        } else {
            js = "(function(){var e={};for(var i=0;i<\(storage).length;i++){var k=\(storage).key(i);e[k]=\(storage).getItem(k);}return {entries:e,count:\(storage).length,type:'\(escapedType)'};})()"
        }
        do {
            let result = try await context.evaluateJSReturningJSON(js, tabId: tabId)
            return successResponse(result)
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func setStorage(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        guard let key = body["key"] as? String, let value = body["value"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "key and value required")
        }
        let type = body["type"] as? String ?? "local"
        let storage = type == "session" ? "sessionStorage" : "localStorage"
        let escapedKey = JSEscape.string(key)
        let escapedValue = JSEscape.string(value)
        do {
            _ = try await context.evaluateJS("\(storage).setItem('\(escapedKey)','\(escapedValue)')", tabId: tabId)
            return successResponse()
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "STORAGE_WRITE_FAILED", message: error.localizedDescription)
        }
    }

    @MainActor
    private func clearStorage(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        let type = body["type"] as? String ?? "both"
        do {
            if type == "local" || type == "both" {
                _ = try await context.evaluateJS("localStorage.clear()", tabId: tabId)
            }
            if type == "session" || type == "both" {
                _ = try await context.evaluateJS("sessionStorage.clear()", tabId: tabId)
            }
            return successResponse(["cleared": type])
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "STORAGE_WRITE_FAILED", message: error.localizedDescription)
        }
    }

    // MARK: - Clipboard

    @MainActor
    private func getClipboard() async -> [String: Any] {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        let hasImage = NSPasteboard.general.canReadItem(withDataConformingToTypes: NSImage.imageTypes)
        return successResponse(["text": text, "hasImage": hasImage])
    }

    @MainActor
    private func setClipboard(_ body: [String: Any]) async -> [String: Any] {
        let text = body["text"] as? String ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return successResponse()
    }

    // MARK: - Fullscreen

    @MainActor
    private func setFullscreen(_ body: [String: Any]) async -> [String: Any] {
        let enabled = body["enabled"] as? Bool ?? true
        guard let window = NSApplication.shared.keyWindow else {
            return errorResponse(code: "NO_WINDOW", message: "No active window")
        }
        let isFullscreen = window.styleMask.contains(.fullScreen)
        if enabled != isFullscreen {
            window.toggleFullScreen(nil)
        }
        return successResponse(["enabled": enabled])
    }

    @MainActor
    private func getFullscreen(_ body: [String: Any]) async -> [String: Any] {
        guard let window = NSApplication.shared.keyWindow else {
            return errorResponse(code: "NO_WINDOW", message: "No active window")
        }
        return successResponse(["enabled": window.styleMask.contains(.fullScreen)])
    }

    // MARK: - Viewport

    @MainActor
    private func resizeViewport(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        let viewport = viewportState.resizeViewport(
            width: body["width"] as? Int,
            height: body["height"] as? Int
        )
        do {
            let renderer = try context.resolveRenderer(tabId: tabId)
            await waitForViewportSize(viewport, renderer: renderer)
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
        let stage = viewportState.fullStageDimensions

        return successResponse([
            "viewport": ["width": Int(viewport.width), "height": Int(viewport.height)],
            "originalViewport": ["width": stage.width, "height": stage.height],
            "activePresetId": NSNull()
        ])
    }

    @MainActor
    private func resetViewport(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        let viewport = viewportState.resetViewport()
        do {
            let renderer = try context.resolveRenderer(tabId: tabId)
            await waitForViewportSize(viewport, renderer: renderer)
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
        return successResponse([
            "viewport": ["width": Int(viewport.width), "height": Int(viewport.height)],
            "activePresetId": NSNull()
        ])
    }

    @MainActor
    private func setViewportPreset(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        guard let presetID = body["presetId"] as? String, !presetID.isEmpty else {
            return errorResponse(code: "MISSING_PARAM", message: "presetId is required")
        }
        guard let preset = allMacViewportPresets.first(where: { $0.id == presetID }) else {
            return errorResponse(code: "INVALID_PARAM", message: "Unknown viewport preset id: \(presetID)")
        }
        guard viewportState.availablePresets.contains(where: { $0.id == presetID }) else {
            return [
                "success": false,
                "error": [
                    "code": "INVALID_PARAM",
                    "message": "Viewport preset \(presetID) is not available for the current macOS window geometry",
                    "reason": "unavailable"
                ]
            ]
        }
        guard let viewport = viewportState.selectPreset(presetID) else {
            return errorResponse(code: "INVALID_PARAM", message: "Viewport preset \(presetID) could not be selected")
        }
        do {
            let renderer = try context.resolveRenderer(tabId: tabId)
            await waitForViewportSize(viewport, renderer: renderer)
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }

        return successResponse([
            "activePresetId": preset.id,
            "preset": [
                "id": preset.id,
                "name": preset.name,
                "inches": preset.displaySizeLabel,
                "pixels": preset.pixelResolutionLabel
            ],
            "viewport": [
                "width": Int(viewport.width),
                "height": Int(viewport.height)
            ]
        ])
    }

    @MainActor
    private func isElementObscured(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        guard let selector = body["selector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let escapedSelector = JSEscape.string(selector)
        let js = """
        (function(){var el=document.querySelector('\(escapedSelector)');if(!el)return null;var r=el.getBoundingClientRect();return{element:{selector:'\(escapedSelector)',rect:{x:r.x,y:r.y,width:r.width,height:r.height}},obscured:false,reason:null,keyboardOverlap:null,suggestion:null};})()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js, tabId: tabId)
            if result.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found") }
            return successResponse(result)
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    // MARK: - Iframes

    @MainActor
    private func getIframes(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        let js = """
        (function(){var frames=document.querySelectorAll('iframe');return{iframes:Array.from(frames).map(function(f,i){var r=f.getBoundingClientRect();return{id:i,src:f.src||'',name:f.name||'',selector:'iframe:nth-of-type('+(i+1)+')',rect:{x:r.x,y:r.y,width:r.width,height:r.height},visible:r.width>0&&r.height>0,crossOrigin:false};}),count:frames.length};})()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js, tabId: tabId)
            return successResponse(result)
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func switchToIframe(_ body: [String: Any]) async -> [String: Any] {
        let id = body["iframeId"] as? Int ?? 0
        return successResponse(["iframe": ["id": id, "src": ""], "context": "iframe"])
    }

    @MainActor
    private func waitForViewportSize(_ size: CGSize, renderer: any RendererEngine) async {
        let expectedWidth = size.width
        let expectedHeight = size.height
        let view = renderer.makeView()

        for _ in 0..<30 {
            let bounds = view.bounds.size
            if abs(bounds.width - expectedWidth) < 0.75 &&
               abs(bounds.height - expectedHeight) < 0.75 {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - Tabs

    @MainActor
    private func getTabs() async -> [String: Any] {
        if context.renderer?.engineName == "chromium" {
            return context.cefUnsupportedError(feature: "Tab management")
        }
        guard let store = context.tabStore else {
            return errorResponse(code: "NO_TAB_STORE", message: "Tab store not initialised")
        }
        let tabs: [[String: Any]] = store.tabs.map { tab in
            tabInfoPayload(for: tab, activeID: store.activeTabID)
        }
        return successResponse([
            "tabs": tabs,
            "count": tabs.count,
            "activeTab": store.activeTabID?.uuidString ?? ""
        ])
    }

    @MainActor
    private func tabInfoPayload(for tab: Tab, activeID: UUID?) -> [String: Any] {
        [
            "id": tab.id.uuidString,
            "url": tab.currentURL,
            "title": tab.title,
            "active": tab.id == activeID,
            "isLoading": tab.isLoading
        ]
    }

    @MainActor
    private func newTab(_ body: [String: Any]) async -> [String: Any] {
        if context.renderer?.engineName == "chromium" {
            return context.cefUnsupportedError(feature: "Tab management")
        }
        guard let makeTab = context.onNewTab else {
            return errorResponse(code: "NO_TAB_STORE", message: "Tab store not initialised")
        }
        let tab = makeTab()
        if let urlString = body["url"] as? String,
           let url = URL(string: urlString) {
            context.load(url: url)
        }
        let activeID = context.tabStore?.activeTabID ?? tab.id
        let tabCount = context.tabStore?.tabs.count ?? 1
        return successResponse([
            "tab": tabInfoPayload(for: tab, activeID: activeID),
            "tabCount": tabCount
        ])
    }

    @MainActor
    private func switchTab(_ body: [String: Any]) async -> [String: Any] {
        if context.renderer?.engineName == "chromium" {
            return context.cefUnsupportedError(feature: "Tab switching")
        }
        guard let store = context.tabStore,
              let switchFn = context.onSwitchTab else {
            return errorResponse(code: "NO_TAB_STORE", message: "Tab store not initialised")
        }
        guard let tabIdStr = body["tabId"] as? String,
              let tabId = UUID(uuidString: tabIdStr) else {
            return errorResponse(code: "MISSING_PARAM", message: "tabId (UUID string) required")
        }
        guard store.tabs.contains(where: { $0.id == tabId }) else {
            return errorResponse(code: "TAB_NOT_FOUND", message: "No tab with id \(tabIdStr)")
        }
        switchFn(tabId)
        guard let tab = store.activeTab else {
            return errorResponse(code: "SWITCH_FAILED", message: "Tab switch failed")
        }
        return successResponse([
            "tab": tabInfoPayload(for: tab, activeID: store.activeTabID)
        ])
    }

    @MainActor
    private func closeTab(_ body: [String: Any]) async -> [String: Any] {
        if context.renderer?.engineName == "chromium" {
            return context.cefUnsupportedError(feature: "Tab management")
        }
        guard let store = context.tabStore,
              let closeFn = context.onCloseTab else {
            return errorResponse(code: "NO_TAB_STORE", message: "Tab store not initialised")
        }
        guard let tabIdStr = body["tabId"] as? String,
              let tabId = UUID(uuidString: tabIdStr) else {
            return errorResponse(code: "MISSING_PARAM", message: "tabId (UUID string) required")
        }
        guard store.tabs.contains(where: { $0.id == tabId }) else {
            return errorResponse(code: "TAB_NOT_FOUND", message: "No tab with id \(tabIdStr)")
        }
        closeFn(tabId)
        let postCloseCount = store.tabs.count
        return successResponse(["closed": tabIdStr, "tabCount": postCloseCount])
    }
}
