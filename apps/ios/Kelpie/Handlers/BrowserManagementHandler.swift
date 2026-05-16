import WebKit

// swiftlint:disable line_length

/// Handles cookies, storage, clipboard, dialogs, keyboard, viewport, and unsupported endpoints.
struct BrowserManagementHandler {
    let context: HandlerContext

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
        router.register("resize-viewport") { body in await resizeViewport(body) }
        router.register("reset-viewport") { _ in await resetViewport() }
        router.register("set-viewport-preset") { body in await setViewportPreset(body) }
        router.register("is-element-obscured") { body in await isElementObscured(body) }

        // Unsupported
        for method in ["set-geolocation", "clear-geolocation", "set-request-interception", "get-intercepted-requests", "clear-request-interception", "set-fullscreen", "get-fullscreen"] {
            router.register(method) { _ in
                errorResponse(code: "PLATFORM_NOT_SUPPORTED", message: "\(method) is not supported on iOS")
            }
        }

        // Iframes
        router.register("get-iframes") { _ in await getIframes() }
        router.register("switch-to-iframe") { body in await switchToIframe(body) }
        router.register("switch-to-main") { _ in successResponse(["context": "main"]) }
        router.register("get-iframe-context") { _ in successResponse(["context": "main"]) }

        // Dialogs
        router.register("get-dialog") { _ in await getDialog() }
        router.register("handle-dialog") { body in await handleDialog(body) }
        router.register("set-dialog-auto-handler") { body in await setDialogAutoHandler(body) }

        // Tabs
        router.register("get-tabs") { _ in await getTabs() }
        router.register("new-tab") { body in await newTab(body) }
        router.register("switch-tab") { body in await switchTab(body) }
        router.register("close-tab") { body in await closeTab(body) }
    }

    // MARK: - Cookies

    @MainActor
    private func getCookies(_ body: [String: Any]) async -> [String: Any] {
        guard let webView = context.webView else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
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
        guard let webView = context.webView,
              let name = body["name"] as? String,
              let value = body["value"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "name and value required")
        }
        var props: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .path: body["path"] as? String ?? "/"]
        if let domain = body["domain"] as? String { props[.domain] = domain } else { props[.domain] = webView.url?.host ?? "localhost" }
        if let cookie = HTTPCookie(properties: props) {
            await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            return successResponse()
        }
        return errorResponse(code: "COOKIE_ERROR", message: "Failed to create cookie")
    }

    @MainActor
    private func deleteCookies(_ body: [String: Any]) async -> [String: Any] {
        guard let webView = context.webView else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let all = await store.allCookies()
        let deleteAll = body["deleteAll"] as? Bool ?? false
        let name = body["name"] as? String
        var deleted = 0
        for cookie in all {
            if deleteAll || cookie.name == name {
                await store.deleteCookie(cookie)
                deleted += 1
            }
        }
        return successResponse(["deleted": deleted])
    }

    // MARK: - Storage

    @MainActor
    private func getStorage(_ body: [String: Any]) async -> [String: Any] {
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
        let escapedKey = JSEscape.string(key)
        let escapedValue = JSEscape.string(value)
        do {
            _ = try await context.evaluateJS("\(storage).setItem('\(escapedKey)','\(escapedValue)')")
            return successResponse()
        } catch {
            return errorResponse(code: "STORAGE_WRITE_FAILED", message: error.localizedDescription)
        }
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
        let text = UIPasteboard.general.string ?? ""
        return successResponse(["text": text, "hasImage": UIPasteboard.general.hasImages])
    }

    @MainActor
    private func setClipboard(_ body: [String: Any]) async -> [String: Any] {
        let text = body["text"] as? String ?? ""
        UIPasteboard.general.string = text
        return successResponse()
    }

    // MARK: - Keyboard

    @MainActor
    private func showKeyboard(_ body: [String: Any]) async -> [String: Any] {
        if let selector = body["selector"] as? String {
            _ = try? await context.evaluateJS("document.querySelector('\(JSEscape.string(selector))')?.focus()")
        }
        let kb = context.keyboardObserver
        let bounds = kb.screenBounds
        return successResponse([
            "keyboardVisible": true,
            "keyboardHeight": Int(kb.height),
            "visibleViewport": ["width": Int(bounds.width), "height": Int(kb.visibleViewportHeight)]
        ])
    }

    @MainActor
    private func hideKeyboard() async -> [String: Any] {
        _ = try? await context.evaluateJS("document.activeElement?.blur()")
        let bounds = context.keyboardObserver.screenBounds
        return successResponse([
            "keyboardVisible": false,
            "visibleViewport": ["width": Int(bounds.width), "height": Int(bounds.height)]
        ])
    }

    @MainActor
    private func getKeyboardState() async -> [String: Any] {
        let kb = context.keyboardObserver
        let bounds = kb.screenBounds
        return successResponse([
            "visible": kb.isVisible,
            "height": Int(kb.height),
            "type": "default",
            "visibleViewport": ["width": Int(bounds.width), "height": Int(kb.visibleViewportHeight)],
            "focusedElement": NSNull()
        ])
    }

    // MARK: - Viewport

    @MainActor
    private func resizeViewport(_ body: [String: Any]) async -> [String: Any] {
        let width = body["width"] as? Int ?? 390
        let height = body["height"] as? Int ?? 844
        UserDefaults.standard.set("", forKey: ipadMobileStagePresetDefaultsKey)
        return successResponse([
            "viewport": ["width": width, "height": height],
            "originalViewport": ["width": 390, "height": 844],
            "activePresetId": NSNull()
        ])
    }

    @MainActor
    private func resetViewport() async -> [String: Any] {
        UserDefaults.standard.set("", forKey: ipadMobileStagePresetDefaultsKey)
        return successResponse([
            "viewport": ["width": 390, "height": 844],
            "activePresetId": NSNull()
        ])
    }

    @MainActor
    private func setViewportPreset(_ body: [String: Any]) async -> [String: Any] {
        guard let presetID = body["presetId"] as? String, !presetID.isEmpty else {
            return errorResponse(code: "MISSING_PARAM", message: "presetId is required")
        }
        guard let preset = tabletViewportPreset(id: presetID) else {
            return errorResponse(code: "INVALID_PARAM", message: "Unknown viewport preset id: \(presetID)")
        }

        let availablePresetIDs = currentTabletViewportAvailablePresetIDs()
        guard availablePresetIDs.contains(preset.id) else {
            return [
                "success": false,
                "error": [
                    "code": "INVALID_PARAM",
                    "message": "Viewport preset \(presetID) is not available for the current device geometry",
                    "reason": "unavailable"
                ]
            ]
        }

        UserDefaults.standard.set(preset.id, forKey: ipadMobileStagePresetDefaultsKey)
        let viewportSize = tabletViewportSize(for: preset, availableSize: currentTabletViewportAvailableSize())

        return successResponse([
            "activePresetId": preset.id,
            "preset": [
                "id": preset.id,
                "name": preset.name,
                "inches": preset.displaySizeLabel,
                "pixels": preset.pixelResolutionLabel
            ],
            "viewport": [
                "width": Int(viewportSize.width),
                "height": Int(viewportSize.height)
            ]
        ])
    }

    @MainActor
    private func isElementObscured(_ body: [String: Any]) async -> [String: Any] {
        guard let selector = body["selector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let js = """
        (function(){var el=document.querySelector('\(JSEscape.string(selector))');if(!el)return null;var r=el.getBoundingClientRect();return{x:r.x,y:r.y,width:r.width,height:r.height,bottom:r.bottom};})()
        """
        do {
            let rect = try await context.evaluateJSReturningJSON(js)
            if rect.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found") }

            let elementBottom = rect["bottom"] as? Double ?? 0
            let kb = context.keyboardObserver
            let visibleHeight = Double(kb.visibleViewportHeight)

            let element: [String: Any] = [
                "selector": selector,
                "rect": [
                    "x": rect["x"] ?? 0,
                    "y": rect["y"] ?? 0,
                    "width": rect["width"] ?? 0,
                    "height": rect["height"] ?? 0
                ]
            ]

            if kb.isVisible && elementBottom > visibleHeight {
                let overlap = Int(elementBottom - visibleHeight)
                return successResponse([
                    "element": element,
                    "obscured": true,
                    "reason": "keyboard",
                    "keyboardOverlap": overlap,
                    "suggestion": "scroll-into-view"
                ])
            }

            return successResponse([
                "element": element,
                "obscured": false,
                "reason": NSNull(),
                "keyboardOverlap": NSNull(),
                "suggestion": NSNull()
            ])
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

    // MARK: - Dialogs

    @MainActor
    private func getDialog() async -> [String: Any] {
        let state = context.dialogState
        guard let dialog = state.current else {
            return successResponse(["showing": false, "dialog": NSNull()])
        }
        var info: [String: Any] = [
            "type": dialog.type.rawValue,
            "message": dialog.message
        ]
        if let defaultText = dialog.defaultText {
            info["defaultValue"] = defaultText
        } else {
            info["defaultValue"] = NSNull()
        }
        return successResponse(["showing": true, "dialog": info])
    }

    @MainActor
    private func handleDialog(_ body: [String: Any]) async -> [String: Any] {
        let action = body["action"] as? String ?? "accept"
        let text = body["promptText"] as? String ?? body["text"] as? String
        let result = context.dialogState.handle(action: action, text: text)
        guard result.handled else {
            return errorResponse(code: "NO_DIALOG", message: "No dialog is currently showing")
        }
        return successResponse(["action": action, "dialogType": result.type.rawValue])
    }

    @MainActor
    private func setDialogAutoHandler(_ body: [String: Any]) async -> [String: Any] {
        let state = context.dialogState
        let enabled = body["enabled"] as? Bool ?? true
        let defaultAction = body["defaultAction"] as? String ?? "accept"

        if enabled {
            if defaultAction == "queue" {
                state.autoHandler = nil
            } else {
                state.autoHandler = defaultAction
            }
        } else {
            state.autoHandler = nil
        }

        state.autoPromptText = body["promptText"] as? String ?? ""
        return successResponse(["enabled": enabled])
    }

    // MARK: - Tabs

    @MainActor
    private func tabInfo(_ tab: BrowserTab, tabStore: TabStore) -> [String: Any] {
        [
            "id": tab.id.uuidString,
            "url": tab.currentURL,
            "title": tab.pageTitle,
            "active": tab.id == tabStore.activeBrowserTabID,
            "isLoading": tab.isLoading
        ]
    }

    @MainActor
    private func getTabs() async -> [String: Any] {
        guard let tabStore = context.tabStore else {
            guard let webView = context.webView else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
            let tab: [String: Any] = [
                "id": "0",
                "url": webView.url?.absoluteString ?? "",
                "title": webView.title ?? "",
                "active": true,
                "isLoading": false
            ]
            return successResponse(["tabs": [tab], "count": 1, "activeTab": "0"])
        }
        let tabs = tabStore.tabs.map { tabInfo($0, tabStore: tabStore) }
        return successResponse([
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
        let tab = tabStore.addBrowserTab(url: url)
        return successResponse(["tab": tabInfo(tab, tabStore: tabStore), "tabCount": tabStore.tabs.count])
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
        return successResponse(["tab": tabInfo(activeTab, tabStore: tabStore)])
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
        return successResponse(["closed": idString, "tabCount": tabStore.tabs.count])
    }

    private func parseTabID(_ body: [String: Any]) -> String? {
        body["tabId"] as? String ?? body["id"] as? String
    }
}
