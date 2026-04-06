import UIKit
import WebKit
import Combine

/// Manages an external display (Apple TV via AirPlay).
/// Uses UIScreen notifications to detect AirPlay, then scans connected scenes
/// for the external display UIWindowScene and creates a fullscreen WKWebView on it.
extension Notification.Name {
    static let externalDisplayConnectionChanged = Notification.Name("externalDisplayConnectionChanged")
}

@MainActor
final class ExternalDisplayManager: ObservableObject {
    static let shared = ExternalDisplayManager()
    static let debugTVSize = CGSize(width: 1920, height: 1080)

    @Published private(set) var isConnected = false
    @Published private(set) var isSyncEnabled = UserDefaults.standard.bool(forKey: "tvSyncEnabled")
    let externalPort: UInt16 = 8421
    var attachPath: String?

    var serverState: ServerState?
    var browserState: BrowserState?
    var externalWindow: UIWindow?
    weak var phoneWebView: WKWebView?

    private var syncTask: Task<Void, Never>?
    private var lastSyncedScrollRatio: Double?
    private var pendingTVURL: String?

    private init() {}

    func startMonitoring() {
        refreshExternalSceneState()

        NotificationCenter.default.addObserver(
            forName: UIScene.willConnectNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshExternalSceneState() }
        }
        NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshExternalSceneState() }
        }
        NotificationCenter.default.addObserver(
            forName: UIScene.didDisconnectNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshExternalSceneState() }
        }
    }

    private func attach(to windowScene: UIWindowScene) {
        let screen = windowScene.screen
        let screenBounds = screen.bounds

        let bs = BrowserState()
        let ss = ServerState(deviceInfo: DeviceInfo.externalDisplay(
            port: Int(externalPort),
            screenSize: screenBounds.size,
            scale: screen.scale
        ))
        let config = makeTVWebViewConfiguration(serverState: ss)

        // Create the WebView at half the screen size (1920x1080 for 4K TV).
        // This gives a natural 1920px CSS viewport — desktop-width layout.
        // contentScaleFactor=2 makes WebKit render at 3840x2160 pixels (4K).
        // The 2x transform fills the full screen with pixel-perfect quality.
        let cssSize = CGSize(width: screenBounds.width / 2, height: screenBounds.height / 2)

        let vc = UIViewController()
        vc.view.frame = screenBounds
        vc.view.backgroundColor = .black

        let webView = WKWebView(frame: CGRect(origin: .zero, size: cssSize), configuration: config)
        webView.customUserAgent = WebViewDefaults.sharedUserAgent
        webView.contentScaleFactor = 2
        webView.layer.anchorPoint = .zero
        webView.layer.position = .zero
        webView.transform = CGAffineTransform(scaleX: 2, y: 2)
        vc.view.addSubview(webView)

        let window = UIWindow(windowScene: windowScene)
        window.frame = screenBounds
        window.rootViewController = vc
        window.makeKeyAndVisible()

        attach(
            browserState: bs,
            serverState: ss,
            webView: webView,
            window: window,
            attachPath: "scene-scan"
        )
    }

    func attachDebugLocalTV() {
        guard !isConnected else { return }

        let bs = BrowserState()
        let ss = ServerState(deviceInfo: DeviceInfo.externalDisplay(
            port: Int(externalPort),
            screenSize: Self.debugTVSize,
            scale: 1
        ))
        let config = makeTVWebViewConfiguration(serverState: ss)
        let webView = WKWebView(
            frame: CGRect(origin: .zero, size: Self.debugTVSize),
            configuration: config
        )
        webView.customUserAgent = WebViewDefaults.sharedUserAgent

        attach(
            browserState: bs,
            serverState: ss,
            webView: webView,
            window: nil,
            attachPath: "debug-local"
        )
    }

    func detach() {
        guard isConnected else { return }
        stopSyncLoop()
        serverState?.stop()
        externalWindow?.isHidden = true
        externalWindow = nil
        serverState = nil
        browserState = nil
        isConnected = false
        attachPath = nil
        NotificationCenter.default.post(name: .externalDisplayConnectionChanged, object: nil)
    }

    func setPhoneWebView(_ webView: WKWebView?) {
        phoneWebView = webView
        log("phone webview attached url=\(webView?.url?.absoluteString ?? "nil")")
        startSyncLoopIfNeeded()
    }

    func setSyncEnabled(_ enabled: Bool) {
        guard isSyncEnabled != enabled else { return }
        isSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "tvSyncEnabled")
        log("sync enabled changed to \(enabled)")
        if enabled {
            startSyncLoopIfNeeded()
            triggerSyncPass()
        } else {
            stopSyncLoop()
        }
    }

    func triggerSyncPass() {
        guard isSyncEnabled, syncTask != nil else { return }
        Task { @MainActor in
            await performSyncPass()
        }
    }

    private func makeTVWebViewConfiguration(serverState: ServerState) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = WebViewDefaults.sharedWebsiteDataStore

        let ucc = config.userContentController
        ucc.addUserScript(NetworkBridge.bridgeScript)
        ucc.add(serverState.handlerContext, name: "kelpieNetwork")
        ucc.addUserScript(ConsoleHandler.bridgeScript)
        ucc.add(serverState.handlerContext, name: "kelpieConsole")

        return config
    }

    private func attach(
        browserState: BrowserState,
        serverState: ServerState,
        webView: WKWebView,
        window: UIWindow?,
        attachPath: String
    ) {
        if let url = URL(string: browserState.currentURL) {
            webView.load(URLRequest(url: url))
        }

        serverState.webView = webView
        serverState.handlerContext.webView = webView

        self.browserState = browserState
        self.serverState = serverState
        self.externalWindow = window
        isConnected = true
        self.attachPath = attachPath
        NotificationCenter.default.post(name: .externalDisplayConnectionChanged, object: nil)
        log("attached external display via \(attachPath)")

        serverState.startHTTPServer()
        serverState.startMDNS()
        startSyncLoopIfNeeded()

        let coordinator = TVWebViewObserver(browserState: browserState)
        webView.navigationDelegate = coordinator
        objc_setAssociatedObject(webView, &tvObserverKey, coordinator, .OBJC_ASSOCIATION_RETAIN)
    }

    private func refreshExternalSceneState() {
        if let windowScene = findExternalWindowScene() {
            guard !isConnected else { return }
            attach(to: windowScene)
            return
        }

        if externalWindow != nil {
            detach()
        }
    }

    private func findExternalWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { scene in
            guard scene.session.role == .windowExternalDisplayNonInteractive else {
                return nil
            }
            return scene as? UIWindowScene
        }.first
    }

    private func startSyncLoopIfNeeded() {
        guard isSyncEnabled, isConnected, phoneWebView != nil, syncTask == nil else { return }
        log("starting sync loop")
        syncTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                guard self.isSyncEnabled, self.isConnected, self.phoneWebView != nil else {
                    self.log("stopping sync loop due to missing state")
                    self.syncTask = nil
                    return
                }
                await self.performSyncPass()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            self?.syncTask = nil
        }
    }

    private func stopSyncLoop() {
        syncTask?.cancel()
        syncTask = nil
        lastSyncedScrollRatio = nil
        pendingTVURL = nil
    }

    private struct PageSyncSnapshot {
        let urlString: String
        let scrollRatio: Double
    }

    private func performSyncPass() async {
        guard isSyncEnabled, let phoneWebView else { return }
        guard let snapshot = await pageSnapshot(from: phoneWebView) else {
            log("phone snapshot unavailable")
            return
        }
        log("phone snapshot url=\(snapshot.urlString.prefix(80)) ratio=\(String(format: "%.3f", snapshot.scrollRatio))")
        guard syncURLToTV(snapshot.urlString) else { return }
        guard let tvWebView = serverState?.handlerContext.webView else {
            log("tv webview unavailable")
            return
        }

        if let lastSyncedScrollRatio,
           abs(lastSyncedScrollRatio - snapshot.scrollRatio) < 0.001 {
            return
        }

        do {
            try await tvWebView.evaluateJavaScript(
                """
                (function(targetRatio) {
                    var doc = document.documentElement;
                    var maxScroll = Math.max((doc ? doc.scrollHeight : 0) - window.innerHeight, 0);
                    var state = window.__kelpieSyncState || (window.__kelpieSyncState = {
                        raf: 0,
                        targetY: 0
                    });
                    state.targetY = targetRatio * maxScroll;

                    if (state.raf) {
                        return;
                    }

                    var step = function() {
                        var currentY = window.scrollY ?? window.pageYOffset ?? (doc ? doc.scrollTop : 0) ?? 0;
                        var delta = state.targetY - currentY;
                        if (Math.abs(delta) < 0.5) {
                            window.scrollTo(0, state.targetY);
                            state.raf = 0;
                            return;
                        }

                        window.scrollTo(0, currentY + delta * 0.28);
                        state.raf = window.requestAnimationFrame(step);
                    };

                    state.raf = window.requestAnimationFrame(step);
                })(\(snapshot.scrollRatio))
                """
            )
            lastSyncedScrollRatio = snapshot.scrollRatio
            log("applied tv scroll ratio=\(String(format: "%.3f", snapshot.scrollRatio))")
        } catch {
            lastSyncedScrollRatio = nil
            log("tv scroll apply failed: \(error.localizedDescription)")
        }
    }

    private func pageSnapshot(from webView: WKWebView) async -> PageSyncSnapshot? {
        let script = """
        (function() {
            var doc = document.documentElement;
            var body = document.body;
            var scrollHeight = Math.max(doc ? doc.scrollHeight : 0, body ? body.scrollHeight : 0);
            var viewportHeight = window.innerHeight || (doc ? doc.clientHeight : 0) || 0;
            var maxScroll = Math.max(scrollHeight - viewportHeight, 0);
            var scrollY = window.scrollY ?? window.pageYOffset ?? (doc ? doc.scrollTop : 0) ?? 0;
            return JSON.stringify({
                url: String(window.location.href || ''),
                scrollRatio: maxScroll > 0 ? Math.min(Math.max(scrollY / maxScroll, 0), 1) : 0
            });
        })()
        """

        do {
            guard let jsonString = try await webView.evaluateJavaScript(script) as? String,
                  let data = jsonString.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlString = json["url"] as? String,
                  !urlString.isEmpty else {
                return nil
            }

            let scrollRatio = json["scrollRatio"] as? Double ?? 0
            return PageSyncSnapshot(
                urlString: urlString,
                scrollRatio: min(max(scrollRatio, 0), 1)
            )
        } catch {
            return nil
        }
    }

    @discardableResult
    private func syncURLToTV(_ urlString: String) -> Bool {
        guard isSyncEnabled,
              let tvWebView = serverState?.handlerContext.webView,
              let url = URL(string: urlString) else {
            log("syncURLToTV blocked connected=\(isConnected) sync=\(isSyncEnabled) tvExists=\(serverState?.handlerContext.webView != nil)")
            return false
        }

        if tvWebView.url?.absoluteString == urlString {
            if tvWebView.isLoading {
                lastSyncedScrollRatio = nil
                log("tv url matched but still loading")
                return false
            }
            pendingTVURL = nil
            log("tv url already matched")
            return true
        }

        if pendingTVURL != urlString {
            pendingTVURL = urlString
            log("loading tv url from \(tvWebView.url?.absoluteString ?? "nil") to \(urlString.prefix(80))")
            tvWebView.load(URLRequest(url: url))
        } else {
            log("tv still pending \(urlString.prefix(80)) current=\(tvWebView.url?.absoluteString ?? "nil")")
        }
        lastSyncedScrollRatio = nil
        return false
    }

    private func log(_ message: String) {
        guard ProcessInfo.processInfo.environment["KELPIE_SYNC_LOG"] == "1" else { return }
        NSLog("[TVSync] %@", message)
    }
}

private var tvObserverKey: UInt8 = 0

/// Minimal WKNavigationDelegate to sync BrowserState for the TV WebView.
private class TVWebViewObserver: NSObject, WKNavigationDelegate {
    let browserState: BrowserState

    init(browserState: BrowserState) {
        self.browserState = browserState
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            browserState.currentURL = webView.url?.absoluteString ?? ""
            browserState.pageTitle = webView.title ?? ""
            browserState.isLoading = false
            HistoryStore.shared.record(url: browserState.currentURL, title: browserState.pageTitle)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            browserState.isLoading = true
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor in
            browserState.currentURL = webView.url?.absoluteString ?? ""
            browserState.pageTitle = webView.title ?? ""
        }
    }
}
