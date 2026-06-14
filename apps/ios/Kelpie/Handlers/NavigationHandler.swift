import WebKit

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
              let webView = context.webView else {
            return errorResponse(code: "INVALID_URL", message: "Missing or invalid URL")
        }
        let timeout = (body["timeout"] as? Int) ?? 10000
        let iterations = max(timeout / 100, 1)
        let start = CFAbsoluteTimeGetCurrent()
        context.lastNavigationError = nil
        webView.load(URLRequest(url: url))

        // Wait for the load to finish. A captured error is only fatal once the page is no
        // longer loading — while `isLoading` is true a superseded/redirecting load may have
        // recorded a stale error that the genuine load will clear on its next start.
        var didFinish = false
        for _ in 0..<iterations {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if !webView.isLoading {
                didFinish = true
                break
            }
        }

        // The page settled: report success unless a genuine load failure was captured. An error
        // alongside a finished, non-loading page (e.g. a real DNS/TLS failure) is a true error;
        // benign cancellations were already filtered out in the navigation delegate.
        if didFinish {
            if let error = context.lastNavigationError {
                return errorResponse(code: "NAVIGATION_ERROR", message: error)
            }
            let loadTime = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            return successResponse([
                "url": webView.url?.absoluteString ?? urlString,
                "title": webView.title ?? "",
                "loadTime": loadTime
            ])
        }

        // Loop expired without the page settling. Surface a captured error if one exists,
        // otherwise treat the unfinished load as a timeout.
        if let error = context.lastNavigationError {
            return errorResponse(code: "NAVIGATION_ERROR", message: error)
        }
        return errorResponse(code: "TIMEOUT", message: "Navigation did not complete within \(timeout)ms")
    }

    @MainActor
    private func back() async -> [String: Any] {
        guard let webView = context.webView else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        webView.goBack()
        try? await Task.sleep(nanoseconds: 500_000_000)
        return successResponse(["url": webView.url?.absoluteString ?? "", "title": webView.title ?? ""])
    }

    @MainActor
    private func forward() async -> [String: Any] {
        guard let webView = context.webView else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        webView.goForward()
        try? await Task.sleep(nanoseconds: 500_000_000)
        return successResponse(["url": webView.url?.absoluteString ?? "", "title": webView.title ?? ""])
    }

    @MainActor
    private func reload() async -> [String: Any] {
        guard let webView = context.webView else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        let start = CFAbsoluteTimeGetCurrent()
        webView.reload()
        for _ in 0..<100 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !webView.isLoading { break }
        }
        let loadTime = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        return successResponse(["url": webView.url?.absoluteString ?? "", "title": webView.title ?? "", "loadTime": loadTime])
    }

    @MainActor
    private func getCurrentUrl() async -> [String: Any] {
        // Prefer the active tab's own stored state — context.webView may lag
        // behind tab switches, returning a stale inactive tab's URL.
        if let tab = context.tabStore?.activeBrowserTab {
            return ["url": tab.currentURL, "title": tab.pageTitle]
        }
        guard let webView = context.webView else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        return ["url": webView.url?.absoluteString ?? "", "title": webView.title ?? ""]
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
