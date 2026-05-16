import AppKit

/// Chromium-based renderer conforming to RendererEngine.
/// Wraps CEFBridge (Obj-C++) and bridges callbacks to async/await.
@MainActor
final class CEFRenderer: RendererEngine {
    final class CookieContinuationState: @unchecked Sendable {
        var didResume = false
    }

    final class CEFHostView: NSView {
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

    var bridge: CEFBridge?
    let containerView: CEFHostView
    private var pendingURL: URL?
    /// Navigation deferred because the view was hidden when load(url:) was called.
    /// Executed by onBoundsReady when the view becomes visible.
    private var pendingNavigation: URL?
    private var documentNavigationStart = Date()
    private var capturedDocumentResponseURL: String?
    var pendingCookies: [HTTPCookie] = []
    var pendingDeleteAllCookies = false
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
