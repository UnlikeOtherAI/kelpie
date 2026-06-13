import Foundation

/// Handles navigate, back, forward, reload, getCurrentUrl.
struct NavigationHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("navigate") { body in await navigate(body) }
        router.register("back") { body in await back(body) }
        router.register("forward") { body in await forward(body) }
        router.register("reload") { body in await reload(body) }
        router.register("get-current-url") { body in await getCurrentUrl(body) }
        router.register("set-home") { body in setHome(body) }
        router.register("get-home") { _ in getHome() }
    }

    @MainActor
    private func navigate(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        guard let urlString = body["url"] as? String,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return errorResponse(code: "INVALID_URL", message: "Missing or invalid URL")
        }
        do {
            let renderer = try context.resolveRenderer(tabId: tabId)
            let start = CFAbsoluteTimeGetCurrent()
            // Drive the SAME renderer reads resolve to, so navigate works even
            // when no window has rendered to wire context.renderer to the active
            // tab — i.e. headless / background, the MCP-controlled mode (#78).
            context.prepareForNavigation()
            renderer.load(url: url)

            let timeout = (body["timeout"] as? Int) ?? 10000
            let iterations = max(timeout / 100, 1)
            for _ in 0..<iterations {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if !renderer.isLoading { break }
            }

            let loadTime = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            let snapshot = await NavigationPageSnapshot.read(from: renderer, fallbackURL: urlString)
            let finalURL = snapshot.url
            // Honest failure (Chromium only): after a real load CEF reports the
            // live document URL, so a renderer still on about:blank / no URL here
            // means the page never loaded — report it instead of a false success
            // that leaves callers reading a blank document (#78/#79). WebKit
            // updates currentURL asynchronously (KVO), so a blank check there
            // would false-positive on fast or redirecting loads; keep WebKit's
            // lenient fallback to the requested URL.
            if context.activeEngineIsChromium, finalURL.isEmpty || finalURL == "about:blank" {
                return errorResponse(
                    code: "NAVIGATION_ERROR",
                    message: "Navigation to \(urlString) did not load — the active renderer is still blank."
                )
            }
            return successResponse([
                "url": finalURL.isEmpty ? urlString : finalURL,
                "title": snapshot.title,
                "loadTime": loadTime
            ])
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
    }

    @MainActor
    private func back(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        do {
            let renderer = try context.resolveRenderer(tabId: tabId)
            if tabId == nil {
                context.goBack()
            } else {
                renderer.goBack()
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            let snapshot = await NavigationPageSnapshot.read(from: renderer)
            return successResponse(["url": snapshot.url, "title": snapshot.title])
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
    }

    @MainActor
    private func forward(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        do {
            let renderer = try context.resolveRenderer(tabId: tabId)
            if tabId == nil {
                context.goForward()
            } else {
                renderer.goForward()
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            let snapshot = await NavigationPageSnapshot.read(from: renderer)
            return successResponse(["url": snapshot.url, "title": snapshot.title])
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
    }

    @MainActor
    private func reload(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        do {
            let renderer = try context.resolveRenderer(tabId: tabId)
            let start = CFAbsoluteTimeGetCurrent()
            if tabId == nil {
                context.reloadPage()
            } else {
                renderer.reload()
            }
            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if !renderer.isLoading { break }
            }
            let loadTime = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            let snapshot = await NavigationPageSnapshot.read(from: renderer)
            return successResponse([
                "url": snapshot.url,
                "title": snapshot.title,
                "loadTime": loadTime
            ])
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
    }

    @MainActor
    private func getCurrentUrl(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        let windowId = HandlerContext.windowId(from: body)
        // Prefer the active tab's own stored state — context.renderer may lag
        // behind tab switches, returning a stale inactive tab's URL (issue #17).
        // This tab-store shortcut is WebKit-only: in Chromium (CEF) mode the
        // tab store holds a hidden about:blank WKWebViewRenderer, so reading it
        // would report "Start Page" while CEF is on a real page (#78). CEF falls
        // through to the live renderer via resolveRenderer below.
        if tabId == nil,
           !context.activeEngineIsChromium,
           let store = context.tabStore(windowId: windowId, tabId: nil),
           let tab = store.activeTab {
            return ["url": tab.currentURL, "title": tab.title]
        }
        do {
            let renderer = try context.resolveRenderer(windowId: windowId, tabId: tabId)
            return ["url": renderer.currentURL?.absoluteString ?? "", "title": renderer.currentTitle]
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "NO_WEBVIEW", message: error.localizedDescription)
        }
    }

    private func setHome(_ body: [String: Any]) -> [String: Any] {
        guard let url = body["url"] as? String, !url.isEmpty else {
            return errorResponse(code: "MISSING_PARAM", message: "url is required")
        }
        UserDefaults.standard.set(url, forKey: "homeURL")
        return successResponse(["url": url])
    }

    private func getHome() -> [String: Any] {
        let url = UserDefaults.standard.string(forKey: "homeURL") ?? defaultHomeURL
        return successResponse(["url": url])
    }
}
