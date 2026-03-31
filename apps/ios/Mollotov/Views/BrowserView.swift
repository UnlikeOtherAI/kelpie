import SwiftUI
import WebKit

/// Main browser screen: URL bar + WKWebView + floating action menu.
struct BrowserView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var serverState: ServerState
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var showHistory = false
    @State private var showNetworkInspector = false
    @AppStorage("hideWelcomeCard") private var hideWelcome = false
    @State private var showWelcome = true
    @State private var webView: WKWebView?
    @AppStorage("debugOverlay") private var debugOverlayEnabled = false
    @State private var debugText = ""
    private let safariAuth = SafariAuthHelper()
    private let debugTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    // FAB side shared with TV controls (1 = right, -1 = left)
    @State private var fabSide: CGFloat = 1

    // External display controls
    @State private var externalDisplayConnected = false
    @State private var syncEnabled = false
    @State private var touchpadMode = false

    // Scroll sync — timer polls phone scroll position and syncs to TV
    private let syncTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var lastSyncedY: CGFloat = -1

    var body: some View {
        ZStack {
            if touchpadMode {
                TouchpadOverlayView(onClose: { exitTouchpadMode() })
            } else {
                browserContent
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .externalDisplayConnectionChanged)) { _ in
            externalDisplayConnected = ExternalDisplayManager.shared.isConnected
            if !externalDisplayConnected {
                syncEnabled = false
                touchpadMode = false
            }
        }
        .onAppear {
            externalDisplayConnected = ExternalDisplayManager.shared.isConnected
        }
    }

    @ViewBuilder
    private var browserContent: some View {
        ZStack {
            VStack(spacing: 0) {
                if browserState.isLoading {
                    ProgressView(value: browserState.progress)
                        .progressViewStyle(.linear)
                }

                URLBarView(
                    browserState: browserState,
                    onNavigate: { url in
                        guard let webView, let urlObj = URL(string: url) else { return }
                        webView.load(URLRequest(url: urlObj))
                    },
                    onBack: { webView?.goBack() },
                    onForward: { webView?.goForward() }
                )

                WebViewContainer(browserState: browserState, handlerContext: serverState.handlerContext) { wv in
                    webView = wv
                    serverState.webView = wv
                    serverState.handlerContext.webView = wv
                }
            }

            if showWelcome && !hideWelcome {
                WelcomeCardView { showWelcome = false }
                    .transition(.opacity)
                    .zIndex(10)
            }

            FloatingMenuView(
                onReload: { webView?.reload() },
                onSafariAuth: {
                    guard let webView, let url = webView.url else { return }
                    safariAuth.authenticate(url: url, webView: webView)
                },
                onSettings: { showSettings = true },
                onBookmarks: { showBookmarks = true },
                onHistory: { showHistory = true },
                onNetworkInspector: { showNetworkInspector = true },
                side: $fabSide
            )

            if externalDisplayConnected {
                TVControlsView(
                    fabSide: fabSide,
                    syncEnabled: $syncEnabled,
                    onTouchpad: { enterTouchpadMode() }
                )
            }
        }
        .overlay(alignment: .bottomLeading) {
            if debugOverlayEnabled {
                Text(debugText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.75))
                    .cornerRadius(6)
                    .padding(8)
            }
        }
        .onReceive(debugTimer) { _ in if debugOverlayEnabled { updateDebug() } }
        .onChange(of: debugOverlayEnabled) { enabled in if enabled { updateDebug() } }
        .onReceive(syncTimer) { _ in pollScrollSync() }
        .ignoresSafeArea(.container, edges: .bottom)
        .onChange(of: browserState.currentURL) { newURL in
            HistoryStore.shared.record(url: newURL, title: browserState.pageTitle)
            syncURLToTV(newURL)
        }
        .onChange(of: syncEnabled) { enabled in
            if enabled, let webView, let url = webView.url {
                syncURLToTV(url.absoluteString)
            }
            if !enabled { lastSyncedY = -1 }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(serverState: serverState)
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView(
                currentTitle: browserState.pageTitle,
                currentURL: browserState.currentURL,
                onNavigate: { url in
                    guard let webView, let urlObj = URL(string: url) else { return }
                    webView.load(URLRequest(url: urlObj))
                }
            )
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(onNavigate: { url in
                guard let webView, let urlObj = URL(string: url) else { return }
                webView.load(URLRequest(url: urlObj))
            })
        }
        .sheet(isPresented: $showNetworkInspector) {
            NetworkInspectorView()
        }
    }

    // MARK: - Scroll Sync

    private func pollScrollSync() {
        guard syncEnabled, let webView else { return }
        let y = webView.scrollView.contentOffset.y
        guard y != lastSyncedY else { return }
        lastSyncedY = y

        let sv = webView.scrollView
        let maxScroll = sv.contentSize.height - sv.bounds.height
        guard maxScroll > 0 else { return }
        let ratio = min(max(y / maxScroll, 0), 1)

        guard let tvWV = ExternalDisplayManager.shared.serverState?.handlerContext.webView else { return }
        tvWV.evaluateJavaScript(
            "window.scrollTo(0,\(ratio)*Math.max(document.documentElement.scrollHeight-window.innerHeight,0))"
        )
    }

    private func syncURLToTV(_ urlString: String) {
        guard syncEnabled,
              let tvWV = ExternalDisplayManager.shared.serverState?.handlerContext.webView,
              let url = URL(string: urlString) else { return }
        if tvWV.url?.absoluteString != urlString {
            tvWV.load(URLRequest(url: url))
        }
    }

    // MARK: - Touchpad Mode

    private func enterTouchpadMode() {
        touchpadMode = true
        OrientationManager.shared.lock = .landscape
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    private func exitTouchpadMode() {
        touchpadMode = false
        OrientationManager.shared.lock = .all
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    // MARK: - Debug Overlay

    private func updateDebug() {
        let screens = UIScreen.screens
        let mgr = ExternalDisplayManager.shared
        var lines: [String] = []

        for (i, s) in screens.enumerated() {
            let o = s.bounds.origin
            lines.append("scr[\(i)] \(Int(o.x)),\(Int(o.y)) \(Int(s.bounds.width))x\(Int(s.bounds.height)) @\(Int(s.scale))x nat=\(Int(s.nativeScale))x mir=\(s.mirrored != nil)")
        }

        lines.append("ext: \(mgr.isConnected ? "ON" : "off") sync=\(syncEnabled)")

        if let win = mgr.externalWindow {
            let wf = win.frame
            lines.append("win: \(Int(wf.width))x\(Int(wf.height))")
        }
        if let wv = mgr.serverState?.handlerContext.webView {
            let b = wv.bounds
            lines.append("wv: \(Int(b.width))x\(Int(b.height)) csf=\(String(format: "%.0f", wv.contentScaleFactor))")
        }

        lines.append("phone: port \(serverState.deviceInfo.port)")
        debugText = lines.joined(separator: "\n")
    }
}
