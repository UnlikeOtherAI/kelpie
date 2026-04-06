import AppKit

/// Chromium-based renderer conforming to RendererEngine.
/// Wraps CEFBridge (Obj-C++) and bridges callbacks to async/await.
@MainActor
final class CEFRenderer: RendererEngine {
    private final class CookieContinuationState: @unchecked Sendable {
        var didResume = false
    }

    private final class CEFHostView: NSView {
        var onWindowReady: (() -> Void)?
        var onBoundsReady: (() -> Void)?
        var onWindowLost: (() -> Void)?
        var onBecomeVisible: (() -> Void)?
        var onBecomeHidden: (() -> Void)?

        override var isHidden: Bool {
            didSet {
                guard isHidden != oldValue else { return }
                if isHidden { onBecomeHidden?() } else { onBecomeVisible?() }
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                onWindowLost?()
            } else {
                notifyIfReady()
            }
        }

        override func layout() {
            super.layout()
            notifyIfReady()
        }

        private func notifyIfReady() {
            guard window != nil else { return }
            guard bounds.width > 0, bounds.height > 0 else { return }
            onWindowReady?()
            onBoundsReady?()
        }
    }

    let engineName = "chromium"

    private static var cefInitialized = false
    private static var messageLoopTimer: Timer?

    private var bridge: CEFBridge?
    private let containerView: CEFHostView
    private var pendingURL: URL?
    /// Navigation deferred because the view was hidden when load(url:) was called.
    /// Executed by onBoundsReady when the view becomes visible.
    private var pendingNavigation: URL?
    private var documentNavigationStart = Date()
    private var capturedDocumentResponseURL: String?
    private var pendingCookies: [HTTPCookie] = []
    private var pendingDeleteAllCookies = false
    private var surfaceRefreshTask: Task<Void, Never>?
    private(set) var currentURL: URL?
    private(set) var currentTitle: String = ""
    private(set) var isLoading: Bool = false
    private(set) var canGoBack: Bool = false
    private(set) var canGoForward: Bool = false
    private(set) var estimatedProgress: Double = 0.0

    var onStateChange: (() -> Void)?
    var onScriptMessage: ((_ name: String, _ body: [String: Any]) -> Void)?

    /// Initialize CEF on a clean run loop iteration. Must be called before
    /// creating any CEFRenderer instance during a live renderer switch.
    /// Safe to call multiple times — only the first call initializes.
    static func ensureCEFInitialized() {
        guard !cefInitialized else { return }
        let ok = CEFBridge.initializeCEF()
        cefInitialized = ok
        if ok {
            messageLoopTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
                CEFBridge.doMessageLoopWork()
            }
        } else {
            NSLog("[CEFRenderer] CEF initialization failed")
        }
    }

    deinit {
        surfaceRefreshTask?.cancel()
        bridge?.closeBrowser()
    }

    init() {
        Self.ensureCEFInitialized()

        containerView = CEFHostView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        containerView.wantsLayer = true
        containerView.onWindowReady = { [weak self] in
            Task { @MainActor in
                self?.ensureBridge()
            }
        }
        containerView.onBoundsReady = { [weak self] in
            Task { @MainActor in
                guard let self, let bridge = self.bridge else { return }
                bridge.resize(to: self.containerView.bounds.size)
            }
        }
        containerView.onBecomeHidden = { [weak self] in
            self?.bridge?.setHidden(true)
        }
        containerView.onBecomeVisible = { [weak self] in
            Task { @MainActor in
                self?.bridge?.setHidden(false)
                self?.scheduleSurfaceRefresh()
                await self?.flushDeferredStateIfPossible()
            }
        }
    }

    private func ensureBridge() {
        guard Self.cefInitialized else { return }
        guard bridge == nil else { return }
        guard containerView.window != nil else { return }
        guard containerView.bounds.width > 0, containerView.bounds.height > 0 else { return }

        NSLog(
            "[CEFRenderer] ensureBridge window=%@ frame=%@ bounds=%@ pendingURL=%@",
            String(describing: containerView.window),
            NSStringFromRect(containerView.frame),
            NSStringFromRect(containerView.bounds),
            pendingURL?.absoluteString ?? "nil"
        )

        let bridge = CEFBridge(
            parentView: containerView,
            url: "about:blank",
            identifier: "main"
        )
        configureBridge(bridge)
        self.bridge = bridge
        bridge.resize(to: containerView.bounds.size)

        let hasCookieWork = !pendingCookies.isEmpty || pendingDeleteAllCookies
        let urlToLoad = pendingURL
        pendingURL = nil

        if hasCookieWork, let urlToLoad {
            // CEF's C API set_cookie consistently returns 0 in external message
            // loop mode — the cookie store is never accessible via the C API.
            // Workaround: load the URL first, then inject cookies via JS after
            // the page loads and reload so they take effect for all requests.
            NSLog(
                "[CEFRenderer] will inject %d cookies via JS after load, url=%@",
                pendingCookies.count,
                urlToLoad.absoluteString
            )
            let cookiesToInject = pendingCookies
            pendingCookies.removeAll()
            pendingDeleteAllCookies = false
            bridge.loadURL(urlToLoad.absoluteString)
            Task { @MainActor [weak self] in
                guard let self, let bridge = self.bridge else { return }
                // Wait for the page to finish loading
                for _ in 0..<200 { // up to ~10s
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    if !bridge.isLoading() { break }
                }
                self.injectCookiesViaJS(cookiesToInject)
            }
        } else if hasCookieWork {
            // Cookie work but no URL — just clear pending state
            pendingCookies.removeAll()
            pendingDeleteAllCookies = false
        } else if let urlToLoad {
            bridge.loadURL(urlToLoad.absoluteString)
        }
    }

    private func configureBridge(_ bridge: CEFBridge) {
        bridge.onStateChange = { [weak self] in
            Task { @MainActor in
                self?.syncState()
            }
        }

        bridge.onConsoleMessage = { [weak self] message in
            Task { @MainActor in
                self?.onScriptMessage?("kelpieConsole", message as? [String: Any] ?? [:])
            }
        }
    }

    private func syncState() {
        let previousLoading = isLoading
        guard let bridge else { return }
        currentURL = URL(string: bridge.currentURL())
        currentTitle = bridge.currentTitle()
        isLoading = bridge.isLoading()
        canGoBack = bridge.canGoBack()
        canGoForward = bridge.canGoForward()
        if isLoading, !previousLoading {
            documentNavigationStart = Date()
            capturedDocumentResponseURL = nil
        } else if !isLoading, previousLoading {
            recordCompletedDocumentNavigation()
        }
        onStateChange?()
    }

    // MARK: - RendererEngine

    func makeView() -> NSView {
        ensureBridge()
        return containerView
    }

    func load(url: URL) {
        NSLog("[CEFRenderer] load url=%@", url.absoluteString)
        let hadBridge = bridge != nil
        pendingURL = url
        currentURL = url
        documentNavigationStart = Date()
        capturedDocumentResponseURL = nil
        ensureBridge()
        if hadBridge {
            if containerView.isHidden {
                // View is hidden (renderer switch in progress). Defer the navigation
                // until the view is shown — CEF crashes if navigated while hidden and
                // then immediately made visible (GPU surface transition).
                pendingNavigation = url
                NSLog("[CEFRenderer] view hidden, deferring navigation to %@", url.absoluteString)
            } else {
                bridge?.loadURL(url.absoluteString)
            }
            pendingURL = nil
        }
    }

    func willDeactivate() {
        bridge?.setHidden(true)
    }

    func didActivate() {
        bridge?.setHidden(false)
        scheduleSurfaceRefresh()
        Task { @MainActor in
            await flushDeferredStateIfPossible()
        }
    }

    func viewportDidChange() {
        scheduleSurfaceRefresh()
    }

    func goBack() { bridge?.goBack() }
    func goForward() { bridge?.goForward() }
    func reload() { bridge?.reload() }
    func hardReload() { bridge?.reloadIgnoringCache() }

    func evaluateJS(_ script: String) async throws -> Any? {
        guard !containerView.isHidden else { return nil }
        guard let bridge else { throw HandlerError.noWebView }
        return try await withCheckedThrowingContinuation { continuation in
            bridge.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let jsonString = result {
                    if let data = jsonString.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                        continuation.resume(returning: parsed)
                    } else {
                        continuation.resume(returning: jsonString)
                    }
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func allCookies() async -> [HTTPCookie] {
        guard let bridge else { return [] }
        return await withCheckedContinuation { continuation in
            let state = CookieContinuationState()

            bridge.getAllCookies { cookieDicts in
                if state.didResume {
                    return
                }
                state.didResume = true

                let cookies = cookieDicts.compactMap { dict -> HTTPCookie? in
                    guard let dict = dict as? [String: Any],
                          let name = dict["name"] as? String,
                          let value = dict["value"] as? String,
                          let domain = dict["domain"] as? String,
                          let path = dict["path"] as? String else { return nil }

                    var props: [HTTPCookiePropertyKey: Any] = [
                        .name: name,
                        .value: value,
                        .domain: domain,
                        .path: path
                    ]
                    if let httpOnly = dict["httpOnly"] as? Bool, httpOnly {
                        props[.init("HttpOnly")] = "TRUE"
                    }
                    if let secure = dict["secure"] as? Bool, secure {
                        props[.secure] = "TRUE"
                    }
                    if let expires = dict["expires"] as? Date {
                        props[.expires] = expires
                    }
                    return HTTPCookie(properties: props)
                }
                continuation.resume(returning: cookies)
            }
        }
    }

    func setCookies(_ cookies: [HTTPCookie]) async {
        guard bridge != nil else {
            if pendingDeleteAllCookies {
                pendingCookies.removeAll()
            }
            pendingCookies.append(contentsOf: cookies)
            return
        }
        // CEF's C API set_cookie doesn't work in external message loop mode.
        // Inject non-httpOnly cookies via JS if we have a loaded page on a
        // matching domain. httpOnly cookies are skipped (JS can't set them).
        // Skip injection while hidden: executing JS while CEF's view is hidden
        // triggers a compositor repaint that crashes CEF's rendering pipeline.
        guard !containerView.isHidden else {
            if pendingDeleteAllCookies {
                pendingCookies.removeAll()
            }
            pendingCookies.append(contentsOf: cookies)
            return
        }
        guard let host = currentURL?.host else { return }
        var js = ""
        for cookie in cookies {
            if cookie.isHTTPOnly { continue }
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard host == domain || host.hasSuffix(".\(domain)") else { continue }
            let cookieName = JSEscape.string(cookie.name)
            let cookieValue = JSEscape.string(cookie.value)
            var parts = "\(cookieName)=\(cookieValue)"
            if !cookie.path.isEmpty { parts += "; path=\(cookie.path)" }
            if !cookie.domain.isEmpty { parts += "; domain=\(cookie.domain)" }
            if cookie.isSecure { parts += "; secure" }
            if let expires = cookie.expiresDate {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                formatter.timeZone = TimeZone(identifier: "GMT")
                parts += "; expires=\(formatter.string(from: expires))"
            }
            js += "document.cookie='\(parts)';\n"
        }
        guard !js.isEmpty else { return }
        _ = try? await evaluateJS(js)
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        let js = "document.cookie = '\(cookie.name)=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=\(cookie.path); domain=\(cookie.domain)';"
        _ = try? await evaluateJS(js)
    }

    func deleteAllCookies() async {
        guard let bridge else {
            pendingDeleteAllCookies = true
            pendingCookies.removeAll()
            return
        }
        guard !containerView.isHidden else {
            pendingDeleteAllCookies = true
            pendingCookies.removeAll()
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            bridge.deleteAllCookies { _ in
                cont.resume()
            }
        }
    }

    func takeSnapshot() async throws -> NSImage {
        guard let bridge else { throw HandlerError.noWebView }
        guard let data = await withCheckedContinuation({ (cont: CheckedContinuation<Data?, Never>) in
            bridge.takeScreenshot { pngData in
                cont.resume(returning: pngData as Data?)
            }
        }) else {
            throw HandlerError.noWebView
        }
        guard let image = NSImage(data: data) else {
            throw HandlerError.noWebView
        }
        return image
    }

    private func injectCookiesViaJS(_ cookies: [HTTPCookie]) {
        guard let bridge, let host = currentURL?.host else { return }
        let matching = cookies.filter { cookie in
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix(".\(domain)")
        }
        guard !matching.isEmpty else { return }
        NSLog("[CEFRenderer] injecting %d cookies via JS for host=%@", matching.count, host)
        var js = ""
        for cookie in matching {
            if cookie.isHTTPOnly { continue }
            let cookieName = JSEscape.string(cookie.name)
            let cookieValue = JSEscape.string(cookie.value)
            var parts = "\(cookieName)=\(cookieValue)"
            if !cookie.path.isEmpty { parts += "; path=\(cookie.path)" }
            if !cookie.domain.isEmpty { parts += "; domain=\(cookie.domain)" }
            if cookie.isSecure { parts += "; secure" }
            if let expires = cookie.expiresDate {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                formatter.timeZone = TimeZone(identifier: "GMT")
                parts += "; expires=\(formatter.string(from: expires))"
            }
            js += "document.cookie='\(parts)';\n"
        }
        guard !js.isEmpty else { return }
        bridge.evaluateJavaScript(js) { [weak self] _, error in
            if let error {
                NSLog("[CEFRenderer] JS cookie injection error: %@", error.localizedDescription)
            } else {
                NSLog("[CEFRenderer] JS cookies injected, reloading")
                Task { @MainActor [weak self] in
                    self?.bridge?.reload()
                }
            }
        }
    }

    private func scheduleSurfaceRefresh() {
        surfaceRefreshTask?.cancel()
        surfaceRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                guard let bridge else { return }
                guard !containerView.isHidden else { continue }
                containerView.layoutSubtreeIfNeeded()
                bridge.setHidden(false)
                bridge.resize(to: containerView.bounds.size)
            }
        }
    }

    private func flushDeferredStateIfPossible() async {
        guard let bridge else { return }
        guard !containerView.isHidden else { return }

        if pendingDeleteAllCookies {
            pendingDeleteAllCookies = false
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                bridge.deleteAllCookies { _ in
                    cont.resume()
                }
            }
        }

        let deferredNavigation = pendingNavigation
        pendingNavigation = nil

        guard !pendingCookies.isEmpty else {
            if let deferredNavigation {
                bridge.loadURL(deferredNavigation.absoluteString)
            }
            return
        }

        let cookiesToInject = pendingCookies
        pendingCookies.removeAll()
        let urlToPrime = deferredNavigation ?? currentURL
        guard let urlToPrime else {
            pendingCookies = cookiesToInject
            return
        }

        bridge.loadURL(urlToPrime.absoluteString)

        for _ in 0..<200 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if !bridge.isLoading() { break }
        }
        injectCookiesViaJS(cookiesToInject)
    }

    private func recordCompletedDocumentNavigation() {
        guard let url = currentURL?.absoluteString,
              !url.isEmpty,
              capturedDocumentResponseURL != url else {
            return
        }

        NetworkTrafficStore.shared.appendDocumentNavigation(
            url: url,
            statusCode: 0,
            contentType: "",
            startedAt: documentNavigationStart
        )
        capturedDocumentResponseURL = url
    }
}
