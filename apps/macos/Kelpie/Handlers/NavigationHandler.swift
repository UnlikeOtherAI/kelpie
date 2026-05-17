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
            if tabId == nil {
                context.load(url: url)
            } else {
                renderer.load(url: url)
            }

            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if !renderer.isLoading { break }
            }

            let loadTime = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            return successResponse([
                "url": renderer.currentURL?.absoluteString ?? urlString,
                "title": renderer.currentTitle,
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
            return successResponse(["url": renderer.currentURL?.absoluteString ?? "", "title": renderer.currentTitle])
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
            return successResponse(["url": renderer.currentURL?.absoluteString ?? "", "title": renderer.currentTitle])
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
            return successResponse([
                "url": renderer.currentURL?.absoluteString ?? "",
                "title": renderer.currentTitle,
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
        if tabId == nil,
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
