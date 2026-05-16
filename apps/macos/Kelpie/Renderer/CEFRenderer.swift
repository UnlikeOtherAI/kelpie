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

        if hasCookieWork {
            if let urlToLoad {
                pendingNavigation = urlToLoad
            }
            Task { @MainActor [weak self] in
                await self?.flushDeferredStateIfPossible()
            }
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
        // Returning `nil` here would be silently coerced into "empty result"
        // by the handler layer (HandlerContext.evaluateJSReturningJSON returns
        // `[:]` for non-JSON output), making callers think the script ran when
        // the renderer was actually hidden. Throw so the response surfaces.
        guard !containerView.isHidden else { throw HandlerError.rendererHidden }
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
        if let cookies = await withCheckedContinuation({ (continuation: CheckedContinuation<[HTTPCookie]?, Never>) in
            bridge.getAllCookiesViaCDP { success, cookieDicts in
                continuation.resume(returning: success ? Self.cookies(from: cookieDicts) : nil)
            }
        }) {
            return cookies
        }

        return await withCheckedContinuation { continuation in
            let state = CookieContinuationState()

            bridge.getAllCookies { cookieDicts in
                if state.didResume {
                    return
                }
                state.didResume = true

                continuation.resume(returning: Self.cookies(from: cookieDicts))
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
        guard !containerView.isHidden else {
            if pendingDeleteAllCookies {
                pendingCookies.removeAll()
            }
            pendingCookies.append(contentsOf: cookies)
            return
        }
        await applyCookiesViaCDP(cookies, primeURLForJSFallback: currentURL, reloadAfterJSErrorFallback: false)
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        guard let bridge else { return }
        let deleted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            bridge.deleteCookie(viaCDP: cookie.name, domain: cookie.domain, path: cookie.path) { success in
                continuation.resume(returning: success)
            }
        }
        if deleted {
            return
        }
        await expireCookiesViaJS([cookie])
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
        let deletedViaCDP = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            bridge.deleteAllCookiesViaCDP { success, _ in
                continuation.resume(returning: success)
            }
        }
        if deletedViaCDP {
            return
        }
        await expireCookiesViaJS(await allCookies())
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

    private func injectCookiesViaJS(_ cookies: [HTTPCookie], reloadAfterInjection: Bool) {
        guard let bridge, let host = currentURL?.host else { return }
        let matching = cookies.filter { cookie in
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix(".\(domain)")
        }
        let js = cookieInjectionScript(for: matching)
        guard !js.isEmpty else { return }
        NSLog("[CEFRenderer] injecting %d cookies via JS for host=%@", matching.count, host)
        bridge.evaluateJavaScript(js) { [weak self] _, error in
            if let error {
                NSLog("[CEFRenderer] JS cookie injection error: %@", error.localizedDescription)
            } else if reloadAfterInjection {
                NSLog("[CEFRenderer] JS cookies injected, reloading")
                Task { @MainActor [weak self] in
                    self?.bridge?.reload()
                }
            }
        }
    }

    nonisolated private static func cookies(from cookieDicts: [Any]) -> [HTTPCookie] {
        cookieDicts.compactMap { item -> HTTPCookie? in
            guard let dict = item as? [String: Any] else { return nil }
            guard let name = dict["name"] as? String,
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
            } else if let expires = dict["expires"] as? NSNumber, expires.doubleValue > 0 {
                props[.expires] = Date(timeIntervalSince1970: expires.doubleValue)
            }
            if let sameSite = dict["sameSite"] as? String, !sameSite.isEmpty {
                props[HTTPCookiePropertyKey("SameSite")] = sameSite
            }
            return HTTPCookie(properties: props)
        }
    }

    private func applyCookiesViaCDP(_ cookies: [HTTPCookie],
                                    primeURLForJSFallback: URL?,
                                    reloadAfterJSErrorFallback: Bool) async {
        guard let bridge else { return }
        var failedCookies: [HTTPCookie] = []

        for cookie in cookies {
            let set = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                bridge.setCookieViaCDP(
                    cookie.name,
                    value: cookie.value,
                    domain: cookie.domain,
                    path: cookie.path,
                    httpOnly: cookie.isHTTPOnly,
                    secure: cookie.isSecure,
                    sameSite: cookie.sameSitePolicy?.rawValue,
                    expires: cookie.expiresDate
                ) { success in
                    continuation.resume(returning: success)
                }
            }

            if !set {
                failedCookies.append(cookie)
            }
        }

        guard !failedCookies.isEmpty else { return }

        if reloadAfterJSErrorFallback, let urlToPrime = primeURLForJSFallback {
            bridge.loadURL(urlToPrime.absoluteString)
            for _ in 0..<200 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if !bridge.isLoading() { break }
            }
        }

        injectCookiesViaJS(failedCookies, reloadAfterInjection: reloadAfterJSErrorFallback)
    }

    private func cookieInjectionScript(for cookies: [HTTPCookie]) -> String {
        var js = ""
        for cookie in cookies where !cookie.isHTTPOnly {
            let cookieName = JSEscape.string(cookie.name)
            let cookieValue = JSEscape.string(cookie.value)
            var parts = "\(cookieName)=\(cookieValue)"
            if !cookie.path.isEmpty { parts += "; path=\(cookie.path)" }
            if !cookie.domain.isEmpty { parts += "; domain=\(cookie.domain)" }
            if cookie.isSecure { parts += "; secure" }
            if let sameSite = cookie.sameSitePolicy?.rawValue, !sameSite.isEmpty {
                parts += "; SameSite=\(sameSite)"
            }
            if let expires = cookie.expiresDate {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                formatter.timeZone = TimeZone(identifier: "GMT")
                parts += "; expires=\(formatter.string(from: expires))"
            }
            js += "document.cookie='\(parts)';\n"
        }
        return js
    }

    private func expireCookiesViaJS(_ cookies: [HTTPCookie]) async {
        let expiredCookies = cookies.map { cookie in
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: "",
                .domain: cookie.domain,
                .path: cookie.path,
                .expires: Date(timeIntervalSince1970: 0)
            ]
            if cookie.isSecure {
                properties[.secure] = "TRUE"
            }
            if let sameSite = cookie.sameSitePolicy?.rawValue, !sameSite.isEmpty {
                properties[HTTPCookiePropertyKey("SameSite")] = sameSite
            }
            return HTTPCookie(properties: properties)
        }
        injectCookiesViaJS(expiredCookies.compactMap { $0 }, reloadAfterInjection: false)
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
            let deleted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                bridge.deleteAllCookiesViaCDP { success, _ in
                    continuation.resume(returning: success)
                }
            }
            if !deleted {
                await expireCookiesViaJS(await allCookies())
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

        let cookiesToApply = pendingCookies
        pendingCookies.removeAll()
        await applyCookiesViaCDP(
            cookiesToApply,
            primeURLForJSFallback: deferredNavigation ?? currentURL,
            reloadAfterJSErrorFallback: true
        )

        if let deferredNavigation {
            bridge.loadURL(deferredNavigation.absoluteString)
        }
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
