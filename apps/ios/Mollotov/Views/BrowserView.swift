import SwiftUI
import WebKit

/// Main browser screen: URL bar + WKWebView + floating action menu.
struct BrowserView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var serverState: ServerState
    @ObservedObject private var externalDisplayManager = ExternalDisplayManager.shared
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var showHistory = false
    @State private var showNetworkInspector = false
    @AppStorage("hideWelcomeCard") private var hideWelcome = false
    @State private var showWelcome = true
    @AppStorage("debugOverlay") private var debugOverlayEnabled = false
    @State private var debugText = ""
    private let safariAuth = SafariAuthHelper()
    private let debugTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    // FAB side shared with TV controls (1 = right, -1 = left)
    @State private var fabSide: CGFloat = 1

    @State private var touchpadMode = false

    var body: some View {
        ZStack {
            if touchpadMode {
                TouchpadOverlayView(onClose: { exitTouchpadMode() })
            } else {
                browserContent
            }
        }
        .onChange(of: externalDisplayManager.isConnected) { connected in
            if !connected {
                touchpadMode = false
            }
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
                    onNavigate: navigate,
                    onBack: goBack,
                    onForward: goForward
                )

                WebViewContainer(browserState: browserState, handlerContext: serverState.handlerContext) { wv in
                    browserState.webView = wv
                    serverState.webView = wv
                    serverState.handlerContext.webView = wv
                    externalDisplayManager.setPhoneWebView(wv)
                }
            }

            if showWelcome && !hideWelcome {
                WelcomeCardView { showWelcome = false }
                    .transition(.opacity)
                    .zIndex(10)
            }

            FloatingMenuView(
                onReload: reload,
                onSafariAuth: authenticateInSafari,
                onSettings: { showSettings = true },
                onBookmarks: { showBookmarks = true },
                onHistory: { showHistory = true },
                onNetworkInspector: { showNetworkInspector = true },
                side: $fabSide
            )

            if externalDisplayManager.isConnected {
                TVControlsView(
                    fabSide: fabSide,
                    syncEnabled: Binding(
                        get: { externalDisplayManager.isSyncEnabled },
                        set: { externalDisplayManager.setSyncEnabled($0) }
                    ),
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
        .ignoresSafeArea(.container, edges: .bottom)
        .onChange(of: browserState.currentURL) { newURL in
            HistoryStore.shared.record(url: newURL, title: browserState.pageTitle)
            externalDisplayManager.triggerSyncPass()
        }
        .onChange(of: browserState.pageTitle) { newTitle in
            HistoryStore.shared.updateLatestTitle(for: browserState.currentURL, title: newTitle)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(serverState: serverState)
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView(
                currentTitle: browserState.pageTitle,
                currentURL: browserState.currentURL,
                onNavigate: navigate
            )
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(onNavigate: navigate)
        }
        .sheet(isPresented: $showNetworkInspector) {
            NetworkInspectorView()
        }
        .onChange(of: serverState.activePanel) { panel in
            guard let panel else { return }
            serverState.activePanel = nil
            // Dismiss any open sheet first
            showHistory = false
            showBookmarks = false
            showNetworkInspector = false
            showSettings = false
            // Delay to let SwiftUI dismiss, then present the new sheet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                switch panel {
                case "history": showHistory = true
                case "bookmarks": showBookmarks = true
                case "network-inspector": showNetworkInspector = true
                case "settings": showSettings = true
                default: break
                }
            }
        }
    }

    private func navigate(_ urlString: String) {
        guard let webView = browserState.webView, let url = URL(string: urlString) else { return }
        webView.load(URLRequest(url: url))
    }

    private func goBack() {
        browserState.webView?.goBack()
    }

    private func goForward() {
        browserState.webView?.goForward()
    }

    private func reload() {
        browserState.webView?.reload()
    }

    private func authenticateInSafari() {
        guard let webView = browserState.webView, let url = webView.url else { return }
        safariAuth.authenticate(url: url, webView: webView)
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

        lines.append("ext: \(mgr.isConnected ? "ON" : "off") sync=\(mgr.isSyncEnabled)")

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
