import AppKit

/// Gecko/Firefox renderer conforming to RendererEngine.
/// Spawns a Firefox subprocess with --remote-debugging-port and drives it
/// via Firefox Remote Protocol (CDP-compatible WebSocket).
@MainActor
final class GeckoRenderer: RendererEngine {
    let engineName = "gecko"

    private let processManager = GeckoProcessManager()
    private let cdp = GeckoCDPClient()
    private let liveView: GeckoLiveView

    private(set) var currentURL: URL?
    private(set) var currentTitle: String = ""
    private(set) var isLoading: Bool = false
    private(set) var canGoBack: Bool = false
    private(set) var canGoForward: Bool = false
    private(set) var estimatedProgress: Double = 0.0

    var onStateChange: (() -> Void)?
    var onScriptMessage: ((_ name: String, _ body: [String: Any]) -> Void)?

    init() {
        liveView = GeckoLiveView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        liveView.wantsLayer = true
        Task { @MainActor in
            await self.startFirefox()
        }
    }

    // MARK: - RendererEngine

    func makeView() -> NSView { liveView }

    func load(url: URL) {
        currentURL = url
        isLoading = true
        onStateChange?()
        Task { @MainActor in
            try? await cdp.send("Page.navigate", params: ["url": url.absoluteString])
            // Firefox CDP does not fire Page.loadEventFired; poll nav history instead.
            await pollUntilLoaded(targetURL: url)
        }
    }

    func goBack() {
        isLoading = true
        Task { @MainActor in
            try? await cdp.send("Page.goBack")
            await pollUntilLoaded(targetURL: nil)
        }
    }

    func goForward() {
        isLoading = true
        Task { @MainActor in
            try? await cdp.send("Page.goForward")
            await pollUntilLoaded(targetURL: nil)
        }
    }

    func reload() {
        isLoading = true
        onStateChange?()
        Task { @MainActor in
            try? await cdp.send("Page.reload")
            await pollUntilLoaded(targetURL: nil)
        }
    }

    /// Firefox CDP does not fire Page.loadEventFired. Poll Page.getNavigationHistory
    /// until the title is non-empty (page loaded) or the deadline passes.
    private func pollUntilLoaded(targetURL: URL?) async {
        let titleBefore = currentTitle
        for _ in 0..<60 {  // up to 6 seconds
            try? await Task.sleep(nanoseconds: 100_000_000)
            await refreshNavHistory()
            let titleChanged = currentTitle != titleBefore
            // A non-empty, changed title reliably signals the page loaded.
            if !currentTitle.isEmpty && titleChanged { break }
            // For about: pages keep polling until URL and title both settle.
        }
        isLoading = false
        estimatedProgress = 1.0
        onStateChange?()
    }

    func evaluateJS(_ script: String) async throws -> Any? {
        let result = try await cdp.send("Runtime.evaluate", params: [
            "expression": script,
            "returnByValue": true,
            "awaitPromise": true,
        ])
        if let exception = result["exceptionDetails"] as? [String: Any] {
            let text = (exception["text"] as? String) ?? "JS exception"
            NSLog("[GeckoRenderer] JS exception: %@", text)
            throw HandlerError.noWebView
        }
        guard let resultObj = result["result"] as? [String: Any] else { return nil }
        return resultObj["value"]
    }

    func allCookies() async -> [HTTPCookie] {
        guard let result = try? await cdp.send("Network.getAllCookies"),
              let cookies = result["cookies"] as? [[String: Any]] else { return [] }
        return cookies.compactMap(makeCookie)
    }

    func setCookies(_ cookies: [HTTPCookie]) async {
        for cookie in cookies {
            var params: [String: Any] = [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path,
                "secure": cookie.isSecure,
                "httpOnly": cookie.isHTTPOnly,
            ]
            if let expires = cookie.expiresDate {
                params["expires"] = expires.timeIntervalSince1970
            }
            try? await cdp.send("Network.setCookie", params: params)
        }
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        try? await cdp.send("Network.deleteCookies", params: [
            "name": cookie.name,
            "domain": cookie.domain,
        ])
    }

    func deleteAllCookies() async {
        let all = await allCookies()
        for cookie in all {
            await deleteCookie(cookie)
        }
    }

    func takeSnapshot() async throws -> NSImage {
        let result = try await cdp.send("Page.captureScreenshot", params: ["format": "png"])
        guard let b64 = result["data"] as? String,
              let data = Data(base64Encoded: b64),
              let image = NSImage(data: data) else {
            throw HandlerError.noWebView
        }
        return image
    }

    // MARK: - Startup

    private func startFirefox() async {
        do {
            try await processManager.start()
            try await cdp.connect(port: processManager.debugPort)
            registerCDPEvents()
            liveView.screenshotProvider = { [weak self] in
                try? await self?.takeSnapshot()
            }
            liveView.startRefreshing()
            try await cdp.send("Page.enable")
            try await cdp.send("Network.enable")
            NSLog("[GeckoRenderer] Firefox started on port %d", processManager.debugPort)
        } catch {
            NSLog("[GeckoRenderer] startup failed: %@", error.localizedDescription)
        }
    }

    private func registerCDPEvents() {
        cdp.on("Page.frameNavigated") { [weak self] params in
            guard let self, let frame = params["frame"] as? [String: Any] else { return }
            if let urlStr = frame["url"] as? String { self.currentURL = URL(string: urlStr) }
            Task { @MainActor in
                await self.refreshNavHistory()
            }
            self.onStateChange?()
        }
        cdp.on("Page.loadEventFired") { [weak self] _ in
            self?.isLoading = false
            self?.estimatedProgress = 1.0
            self?.onStateChange?()
        }
        cdp.on("Page.domContentEventFired") { [weak self] _ in
            self?.estimatedProgress = 0.7
            self?.onStateChange?()
        }
    }

    private func refreshNavHistory() async {
        guard let result = try? await cdp.send("Page.getNavigationHistory"),
              let index = result["currentIndex"] as? Int,
              let entries = result["entries"] as? [[String: Any]] else { return }
        canGoBack = index > 0
        canGoForward = index < entries.count - 1
        if let entry = entries[safe: index] {
            currentTitle = entry["title"] as? String ?? ""
            if let urlStr = entry["url"] as? String { currentURL = URL(string: urlStr) }
        }
        onStateChange?()
    }

    // MARK: - Cookie mapping

    private func makeCookie(_ dict: [String: Any]) -> HTTPCookie? {
        guard let name = dict["name"] as? String,
              let value = dict["value"] as? String,
              let domain = dict["domain"] as? String else { return nil }
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value,
            .domain: domain, .path: dict["path"] as? String ?? "/",
        ]
        if dict["secure"] as? Bool == true { props[.secure] = "TRUE" }
        if let exp = dict["expires"] as? Double, exp > 0 {
            props[.expires] = Date(timeIntervalSince1970: exp)
        }
        return HTTPCookie(properties: props)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
