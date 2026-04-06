import AppKit
import WebKit

// swiftlint:disable line_length

/// Handles cookies, storage, clipboard, dialogs, keyboard, viewport, and unsupported endpoints.
struct BrowserManagementHandler {
    let context: HandlerContext
    let viewportState: ViewportState

    func register(on router: Router) {
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

        // Keyboard & Viewport
        router.register("show-keyboard") { body in await showKeyboard(body) }
        router.register("hide-keyboard") { _ in await hideKeyboard() }
        router.register("get-keyboard-state") { _ in await getKeyboardState() }
        router.register("set-fullscreen") { body in await setFullscreen(body) }
        router.register("get-fullscreen") { _ in await getFullscreen() }
        router.register("resize-viewport") { body in await resizeViewport(body) }
        router.register("reset-viewport") { _ in await resetViewport() }
        router.register("set-viewport-preset") { body in await setViewportPreset(body) }
        router.register("is-element-obscured") { body in await isElementObscured(body) }

        // Unsupported
        for method in ["set-geolocation", "clear-geolocation", "set-request-interception", "get-intercepted-requests", "clear-request-interception"] {
            router.register(method) { _ in
                errorResponse(code: "PLATFORM_NOT_SUPPORTED", message: "\(method) is not supported on macOS")
            }
        }

        // Iframes
        router.register("get-iframes") { _ in await getIframes() }
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
        guard context.renderer != nil else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        let cookies = await context.allCookies()
        let name = body["name"] as? String
        let filtered = name != nil ? cookies.filter { $0.name == name } : cookies
        let cookieList = filtered.map { cookie -> [String: Any] in
            ["name": cookie.name, "value": cookie.value, "domain": cookie.domain, "path": cookie.path,
             "expires": cookie.expiresDate?.description ?? NSNull(), "httpOnly": cookie.isHTTPOnly,
             "secure": cookie.isSecure, "sameSite": cookie.sameSitePolicy?.rawValue ?? ""]
        }
        return successResponse(["cookies": cookieList, "count": cookieList.count])
    }

    @MainActor
    private func setCookie(_ body: [String: Any]) async -> [String: Any] {
        guard context.renderer != nil,
              let name = body["name"] as? String,
              let value = body["value"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "name and value required")
        }
        var props: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .path: body["path"] as? String ?? "/"]
        if let domain = body["domain"] as? String { props[.domain] = domain } else { props[.domain] = context.currentURL?.host ?? "localhost" }
        if let cookie = HTTPCookie(properties: props) {
            await context.setCookie(cookie)
            return successResponse()
        }
        return errorResponse(code: "COOKIE_ERROR", message: "Failed to create cookie")
    }

    @MainActor
    private func deleteCookies(_ body: [String: Any]) async -> [String: Any] {
        guard context.renderer != nil else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        let all = await context.allCookies()
        let deleteAll = body["deleteAll"] as? Bool ?? false
        let name = body["name"] as? String
        var deleted = 0
        if deleteAll {
            deleted = all.count
            await context.deleteAllCookies()
            return successResponse(["deleted": deleted])
        }
        for cookie in all where cookie.name == name {
            await context.deleteCookie(cookie)
            deleted += 1
        }
        return successResponse(["deleted": deleted])
    }

    // MARK: - Storage

    @MainActor
    private func getStorage(_ body: [String: Any]) async -> [String: Any] {
        let type = body["type"] as? String ?? "local"
        let key = body["key"] as? String
        let storage = type == "session" ? "sessionStorage" : "localStorage"
        let js: String
        if let key {
            js = "({entries: {'\(key)': \(storage).getItem('\(key)') || ''}, count: 1, type: '\(type)'})"
        } else {
            js = "(function(){var e={};for(var i=0;i<\(storage).length;i++){var k=\(storage).key(i);e[k]=\(storage).getItem(k);}return {entries:e,count:\(storage).length,type:'\(type)'};})()"
        }
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func setStorage(_ body: [String: Any]) async -> [String: Any] {
        guard let key = body["key"] as? String, let value = body["value"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "key and value required")
        }
        let type = body["type"] as? String ?? "local"
        let storage = type == "session" ? "sessionStorage" : "localStorage"
        _ = try? await context.evaluateJS("\(storage).setItem('\(key)','\(value)')")
        return successResponse()
    }

    @MainActor
    private func clearStorage(_ body: [String: Any]) async -> [String: Any] {
        let type = body["type"] as? String ?? "both"
        if type == "local" || type == "both" { _ = try? await context.evaluateJS("localStorage.clear()") }
        if type == "session" || type == "both" { _ = try? await context.evaluateJS("sessionStorage.clear()") }
        return successResponse(["cleared": type])
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

    // MARK: - Keyboard

    @MainActor
    private func showKeyboard(_ body: [String: Any]) async -> [String: Any] {
        errorResponse(code: "PLATFORM_NOT_SUPPORTED", message: "show-keyboard is not supported on macOS")
    }

    @MainActor
    private func hideKeyboard() async -> [String: Any] {
        errorResponse(code: "PLATFORM_NOT_SUPPORTED", message: "hide-keyboard is not supported on macOS")
    }

    @MainActor
    private func getKeyboardState() async -> [String: Any] {
        errorResponse(code: "PLATFORM_NOT_SUPPORTED", message: "get-keyboard-state is not supported on macOS")
    }

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
    private func getFullscreen() async -> [String: Any] {
        guard let window = NSApplication.shared.keyWindow else {
            return errorResponse(code: "NO_WINDOW", message: "No active window")
        }
        return successResponse(["enabled": window.styleMask.contains(.fullScreen)])
    }

    // MARK: - Viewport

    @MainActor
    private func resizeViewport(_ body: [String: Any]) async -> [String: Any] {
        let viewport = viewportState.resizeViewport(
            width: body["width"] as? Int,
            height: body["height"] as? Int
        )
        await context.waitForViewportSize(viewport)
        let stage = viewportState.fullStageDimensions

        return successResponse([
            "viewport": ["width": Int(viewport.width), "height": Int(viewport.height)],
            "originalViewport": ["width": stage.width, "height": stage.height],
            "activePresetId": NSNull()
        ])
    }

    @MainActor
    private func resetViewport() async -> [String: Any] {
        let viewport = viewportState.resetViewport()
        await context.waitForViewportSize(viewport)
        return successResponse([
            "viewport": ["width": Int(viewport.width), "height": Int(viewport.height)],
            "activePresetId": NSNull()
        ])
    }

    @MainActor
    private func setViewportPreset(_ body: [String: Any]) async -> [String: Any] {
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
        await context.waitForViewportSize(viewport)

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
        guard let selector = body["selector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let js = """
        (function(){var el=document.querySelector('\(JSEscape.string(selector))');if(!el)return null;var r=el.getBoundingClientRect();return{element:{selector:'\(selector)',rect:{x:r.x,y:r.y,width:r.width,height:r.height}},obscured:false,reason:null,keyboardOverlap:null,suggestion:null};})()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            if result.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found") }
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    // MARK: - Iframes

    @MainActor
    private func getIframes() async -> [String: Any] {
        let js = """
        (function(){var frames=document.querySelectorAll('iframe');return{iframes:Array.from(frames).map(function(f,i){var r=f.getBoundingClientRect();return{id:i,src:f.src||'',name:f.name||'',selector:'iframe:nth-of-type('+(i+1)+')',rect:{x:r.x,y:r.y,width:r.width,height:r.height},visible:r.width>0&&r.height>0,crossOrigin:false};}),count:frames.length};})()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func switchToIframe(_ body: [String: Any]) async -> [String: Any] {
        let id = body["iframeId"] as? Int ?? 0
        return successResponse(["iframe": ["id": id, "src": ""], "context": "iframe"])
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
            [
                "id": tab.id.uuidString,
                "url": tab.currentURL,
                "title": tab.title,
                "active": tab.id == store.activeTabID,
                "isLoading": tab.isLoading
            ]
        }
        return successResponse([
            "tabs": tabs,
            "count": tabs.count,
            "activeTab": store.activeTabID?.uuidString ?? NSNull()
        ])
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
        guard let store = context.tabStore else {
            return successResponse(["tab": ["id": tab.id.uuidString, "url": tab.currentURL, "title": tab.title], "tabCount": 1])
        }
        return successResponse([
            "tab": ["id": tab.id.uuidString, "url": tab.currentURL, "title": tab.title],
            "tabCount": store.tabs.count
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
            "tab": ["id": tab.id.uuidString, "url": tab.currentURL, "title": tab.title, "active": true]
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
        return successResponse(["closed": tabIdStr, "tabCount": store.tabs.count])
    }
}
