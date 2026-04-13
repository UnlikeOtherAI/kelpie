import Foundation

/// Handles navigate, back, forward, reload, getCurrentUrl.
struct NavigationHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("navigate") { body in await navigate(body) }
        router.register("back") { _ in await back() }
        router.register("forward") { _ in await forward() }
        router.register("reload") { _ in await reload() }
        router.register("get-current-url") { _ in await getCurrentUrl() }
        router.register("set-home") { body in setHome(body) }
        router.register("get-home") { _ in getHome() }
    }

    @MainActor
    private func navigate(_ body: [String: Any]) async -> [String: Any] {
        guard let urlString = body["url"] as? String,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              context.renderer != nil else {
            return errorResponse(code: "INVALID_URL", message: "Missing or invalid URL")
        }
        let start = CFAbsoluteTimeGetCurrent()
        context.load(url: url)

        for _ in 0..<100 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !context.isLoadingPage { break }
        }

        let loadTime = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        await context.persistRendererCookiesToSharedJar()
        return successResponse([
            "url": context.currentURL?.absoluteString ?? urlString,
            "title": context.currentTitle,
            "loadTime": loadTime
        ])
    }

    @MainActor
    private func back() async -> [String: Any] {
        guard context.renderer != nil else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        context.goBack()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await context.persistRendererCookiesToSharedJar()
        return successResponse(["url": context.currentURL?.absoluteString ?? "", "title": context.currentTitle])
    }

    @MainActor
    private func forward() async -> [String: Any] {
        guard context.renderer != nil else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        context.goForward()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await context.persistRendererCookiesToSharedJar()
        return successResponse(["url": context.currentURL?.absoluteString ?? "", "title": context.currentTitle])
    }

    @MainActor
    private func reload() async -> [String: Any] {
        guard context.renderer != nil else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        let start = CFAbsoluteTimeGetCurrent()
        context.reloadPage()
        for _ in 0..<100 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !context.isLoadingPage { break }
        }
        let loadTime = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        await context.persistRendererCookiesToSharedJar()
        return successResponse(["url": context.currentURL?.absoluteString ?? "", "title": context.currentTitle, "loadTime": loadTime])
    }

    @MainActor
    private func getCurrentUrl() async -> [String: Any] {
        // Prefer the active tab's own stored state — context.renderer may lag
        // behind tab switches, returning a stale inactive tab's URL (issue #17).
        if let tab = context.tabStore?.activeTab {
            return ["url": tab.currentURL, "title": tab.title]
        }
        guard context.renderer != nil else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        return ["url": context.currentURL?.absoluteString ?? "", "title": context.currentTitle]
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
