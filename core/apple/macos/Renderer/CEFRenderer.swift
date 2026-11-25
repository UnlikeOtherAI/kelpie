#if !KELPIE_WEBKIT_ONLY
@_implementationOnly import KelpieChromium
#endif
#if !KELPIE_WEBKIT_ONLY
import AppKit

/// Chromium-based renderer conforming to RendererEngine.
/// Wraps CEFBridge (Obj-C++) and bridges callbacks to async/await.
@MainActor
final class CEFRenderer: RendererEngine {
    final class CEFHostView: NSView {
        var onBoundsReady: (() -> Void)?
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
            notifyIfReady()
        }

        override func layout() {
            super.layout()
            notifyIfReady()
        }

        private func notifyIfReady() {
            guard window != nil else { return }
            guard bounds.width > 0, bounds.height > 0 else { return }
            onBoundsReady?()
        }
    }

    let engineName = "chromium"
    let connectionTabID: String

    private static var cefInitialized = false
    private static var messageLoopTimer: Timer?

    var bridge: CEFBridge?
    let containerView: CEFHostView
    private var pendingURL: URL?
    private var waitingForContext = false
    private var contextReady = false
    private var isActive = false
    private var isRetired = false
    private var documentNavigationStart = Date()
    private var capturedDocumentResponseURL: String?
    private var surfaceRefreshTask: Task<Void, Never>?
    private(set) var currentURL: URL?
    private(set) var currentTitle: String = ""
    var isLoading: Bool { pendingURL != nil || documentLoading }
    private var documentLoading = false
    private(set) var canGoBack: Bool = false
    private(set) var canGoForward: Bool = false
    private(set) var estimatedProgress: Double = 0.0

    var onStateChange: (() -> Void)?
    var onScriptMessage: ((_ name: String, _ body: [String: Any]) -> Void)?
    /// The page opened a new-window link that belongs in a tab.
    var onOpenTab: ((URL) -> Void)?
    let dialogState = DialogState()

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
        MainActor.assumeIsolated { retire() }
    }

    init(tabID: UUID = UUID()) {
        connectionTabID = tabID.uuidString
        Self.ensureCEFInitialized()

        containerView = CEFHostView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        containerView.wantsLayer = true
        containerView.isHidden = true
        containerView.onBoundsReady = { [weak self] in
            Task { @MainActor in
                self?.prepareAttachedSurface()
            }
        }
        containerView.onBecomeVisible = { [weak self] in
            Task { @MainActor in
                guard let self, self.surfaceReady else { return }
                self.bridge?.setHidden(false)
                self.scheduleSurfaceRefresh()
                self.prepareAttachedSurface()
            }
        }
        containerView.onBecomeHidden = { [weak self] in self?.bridge?.setHidden(true) }
    }

    private var surfaceReady: Bool {
        isActive && !isRetired && containerView.window != nil &&
            !containerView.isHiddenOrHasHiddenAncestor && !containerView.bounds.isEmpty
    }

    private func prepareAttachedSurface() {
        guard Self.cefInitialized, surfaceReady else { return }
        guard contextReady else {
            if !waitingForContext {
                waitingForContext = true
                CEFBridge.whenBrowserContextReady { [weak self] in
                    guard let self, !self.isRetired else { return }
                    self.contextReady = true
                    self.prepareAttachedSurface()
                }
            }
            return
        }
        if bridge == nil {
            let bridge = CEFBridge(parentView: containerView, url: "about:blank", identifier: connectionTabID)
            configureBridge(bridge)
            self.bridge = bridge
            scheduleSurfaceRefresh()
        }
        bridge?.resize(to: containerView.bounds.size)
        guard let url = pendingURL else { return }
        pendingURL = nil
        bridge?.loadURL(url.absoluteString)
    }

    func retire() {
        guard !isRetired else { return }
        isRetired = true
        willDeactivate()
        pendingURL = nil
        onStateChange = nil
        onScriptMessage = nil
        onOpenTab = nil
        let view = containerView
        view.isHidden = true
        guard let bridge else {
            view.removeFromSuperview()
            return
        }
        self.bridge = nil
        bridge.retireEmbeddedBrowser { view.removeFromSuperview() }
    }

    private func configureBridge(_ bridge: CEFBridge) {
        bridge.onStateChange = { [weak self] in
            Task { @MainActor in
                self?.syncState()
            }
        }

        bridge.onConsoleMessage = { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                let body = message as? [String: Any] ?? [:]
                BrowserDiagnostics.forTarget(self).recordConsole(body)
                self.onScriptMessage?("kelpieConsole", body)
            }
        }

        bridge.onMicrophoneRequest = { [weak bridge] origin, stillCurrent, resolve in
            guard let site = MacMicrophonePermission.origin(for: URL(string: origin)) else { resolve(false); return }
            MacMicrophonePermission.request(
                site,
                stillCurrent: {
                    guard let bridge, stillCurrent() else { return false }
                    return MacMicrophonePermission.origin(for: URL(string: bridge.currentURL())) == site
                },
                completion: resolve
            )
        }
        bridge.onJavaScriptDialog = { [weak self] type, message, defaultText, resolve in
            Task { @MainActor in
                self?.enqueueJavaScriptDialog(
                    type: type,
                    message: message,
                    defaultText: defaultText,
                    resolve: resolve
                )
            }
        }

        bridge.onOpenTab = { [weak self] url in
            MainActor.assumeIsolated { self?.onOpenTab?(url) }
        }
        bridge.onAppLinkRequest = { [weak self] url, requester in
            MainActor.assumeIsolated {
                guard let self else { return }
                ExternalAppPrompt.present(ExternalAppRequest(url: url, requester: requester), from: self.containerView)
            }
        }
        bridge.onJavaScriptDialogReset = { [weak self] in
            Task { @MainActor in
                self?.dialogState.cancelCurrent()
            }
        }
    }

    private func enqueueJavaScriptDialog(
        type: String,
        message: String,
        defaultText: String?,
        resolve: @escaping (Bool, String?) -> Void
    ) {
        let dialogType = DialogState.DialogType(rawValue: type) ?? .alert
        let dialog = DialogState.PendingDialog(type: dialogType, message: message, defaultText: defaultText) { result in
            resolve(result != nil, result)
        }
        dialogState.enqueue(dialog)
    }

    private func syncState() {
        let previousLoading = documentLoading
        guard let bridge else { return }
        currentURL = URL(string: bridge.currentURL())
        currentTitle = bridge.currentTitle()
        documentLoading = bridge.isLoading()
        estimatedProgress = bridge.loadingProgress()
        canGoBack = bridge.canGoBack()
        canGoForward = bridge.canGoForward()
        if documentLoading, !previousLoading {
            NotificationCenter.default.post(name: .kelpieBrowserDocumentChanged, object: nil)
            documentNavigationStart = Date()
            capturedDocumentResponseURL = nil
            BrowserDiagnostics.forTarget(self).documentResponse = nil
        } else if !documentLoading, previousLoading {
            recordCompletedDocumentNavigation()
            NotificationCenter.default.post(name: .kelpieChromiumDocumentLoaded, object: nil)
        }
        onStateChange?()
    }

    // MARK: - RendererEngine

    func makeView() -> NSView {
        containerView
    }

    func load(url: URL) {
        guard !isRetired else { return }
        pendingURL = url
        estimatedProgress = 0
        currentURL = url
        documentNavigationStart = Date()
        capturedDocumentResponseURL = nil
        BrowserDiagnostics.forTarget(self).documentResponse = nil
        prepareAttachedSurface()
    }

    func willDeactivate() {
        isActive = false
        surfaceRefreshTask?.cancel()
        bridge?.setHidden(true)
    }

    func didActivate() {
        guard !isRetired, !isActive else { return }
        isActive = true
        bridge?.setHidden(false)
        scheduleSurfaceRefresh()
        Task { @MainActor [weak self] in self?.prepareAttachedSurface() }
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

    func evaluateBrowserControlJS(_ script: String) async throws -> Any? {
        guard !containerView.isHidden else { throw HandlerError.rendererHidden }
        guard let bridge else { throw HandlerError.noWebView }
        return try await withCheckedThrowingContinuation { continuation in
            bridge.evaluateBrowserControl(
                script,
                stillVisible: { [weak self] in self?.containerView.isHidden == false },
                completion: { result, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: result) }
                }
            )
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
                guard surfaceReady else { continue }
                containerView.layoutSubtreeIfNeeded()
                bridge.setHidden(false)
                bridge.resize(to: containerView.bounds.size)
            }
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
            statusCode: bridge?.mainFrameHTTPStatusCode() ?? 0,
            contentType: "",
            startedAt: documentNavigationStart
        )
        BrowserDiagnostics.forTarget(self).documentResponse = (url, bridge?.mainFrameHTTPStatusCode() ?? 0, "")
        capturedDocumentResponseURL = url
    }
}
#endif
