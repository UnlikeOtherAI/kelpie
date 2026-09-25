import Combine
import SwiftUI
import WebKit

/// Native browser surface with persistent iPad tabs and collapsing bottom chrome.
struct BrowserView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var serverState: ServerState
    @ObservedObject var tabStore: TabStore
    @ObservedObject var externalDisplayManager = ExternalDisplayManager.shared
    @AppStorage("ipadMobileStageEnabled") var legacyIPadMobileStageEnabled = false
    @AppStorage(ipadMobileStagePresetDefaultsKey) var iPadMobileStagePresetID = ""
    @State var showSettings = false
    @State var showBookmarks = false
    @State var showHistory = false
    @State var showNetworkInspector = false
    @State var showAI = false
    @State var availableIPadViewportPresetIDs: [String] = []
    @AppStorage("hideWelcomeCard") var hideWelcome = false
    @State var showWelcome = true
    @State var welcomePresentationSource: WelcomeCardPresentationSource = .automatic
    @AppStorage("debugOverlay") var debugOverlayEnabled = false
    @State var debugText = ""
    @State var isIn3DInspector = false
    @State var inspectorMode = "rotate"
    @State var bottomBarCollapsed = false
    @State var addressEditing = false
    @State var keyboardBottomInset: CGFloat = 0
    @State var showTabOverview = false
    @StateObject var chromeAppearance = BrowserChromeAppearance()
    @State var chromeSampler = BrowserChromeSampler()
    let safariAuth = SafariAuthHelper()
    let debugTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    // FAB side shared with TV controls (1 = right, -1 = left)
    @State var fabSide: CGFloat = 1

    @State var touchpadMode = false

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
        .pairingDialog(coordinator: serverState.pairingCoordinator)
    }

    @ViewBuilder
    var browserContent: some View {
        ZStack {
            VStack(spacing: 0) {
                if isPad && !serverState.isScriptRecording {
                    TabletTabStrip(tabStore: tabStore, appearance: chromeAppearance)
                }

                if browserState.isLoading && !serverState.isScriptRecording {
                    ProgressView(value: browserState.progress)
                        .progressViewStyle(.linear)
                }

                browserViewport
                    .ignoresSafeArea(.container, edges: .bottom)

            }

            if showWelcome && shouldShowWelcomeCard {
                WelcomeCardView {
                    showWelcome = false
                    welcomePresentationSource = .automatic
                    if let tab = tabStore.activeBrowserTab, tab.isStartPage {
                        tab.isStartPage = false
                        let home = UserDefaults.standard.string(forKey: "homeURL") ?? defaultHomeURL
                        navigate(browserState.currentURL.isEmpty ? home : browserState.currentURL)
                    }
                }
                    .transition(.opacity)
                    .zIndex(10)
            }

            if externalDisplayManager.isConnected && !serverState.isScriptRecording {
                TVControlsView(
                    fabSide: fabSide,
                    syncEnabled: Binding(
                        get: { externalDisplayManager.isSyncEnabled },
                        set: { externalDisplayManager.setSyncEnabled($0) }
                    ),
                    onTouchpad: { enterTouchpadMode() }
                )
            }

            if isIn3DInspector && !serverState.isScriptRecording {
                VStack {
                    Spacer()
                    Inspector3DControlsView(
                        mode: inspectorMode,
                        onSelectMode: { mode in
                            Task { @MainActor in
                                await set3DInspectorMode(mode)
                            }
                        },
                        onZoomOut: {
                            Task { @MainActor in
                                await zoom3DInspector(by: -0.12)
                            }
                        },
                        onZoomIn: {
                            Task { @MainActor in
                                await zoom3DInspector(by: 0.12)
                            }
                        },
                        onReset: {
                            Task { @MainActor in
                                await reset3DInspectorView()
                            }
                        },
                        onExit: {
                            Task { @MainActor in
                                await exit3DInspector()
                            }
                        }
                    )
                    .padding(.bottom, 88)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if serverState.isScriptRecording {
                VStack {
                    HStack {
                        Spacer()
                        RecordingStopButton {
                            serverState.requestScriptAbort()
                        }
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                    }
                    Spacer()
                }
                .zIndex(40)
            }
        }
        .overlay(alignment: .bottom) {
            if !serverState.isScriptRecording && !showTabOverview {
                bottomChrome
                    .padding(.bottom, keyboardBottomInset)
                    .animation(.easeOut(duration: 0.2), value: keyboardBottomInset)
            }
        }
        .background { BrowserKeyboardInset { keyboardBottomInset = $0 } }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .accessibilityHidden(showTabOverview)
        .fullScreenCover(isPresented: $showTabOverview) {
            BrowserTabOverview(tabStore: tabStore) { showTabOverview = false }
        }
        .onChange(of: tabStore.activeBrowserTabID) { _ in bottomBarCollapsed = false }
        .onChange(of: browserState.webView) { _ in updateChromeSample() }
        .onChange(of: browserState.isLoading) { loading in
            if loading { chromeSampler.navigationStarted(); bottomBarCollapsed = false } else { updateChromeSample(); tabStore.captureActivePreview() }
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
        .onAppear { migrateLegacyTabletViewportSelectionIfNeeded() }
        .ignoresSafeArea(.container, edges: serverState.isScriptRecording ? [.top, .bottom] : [])
        .statusBarHidden(serverState.isScriptRecording)
        .onChange(of: browserState.currentURL) { _ in
            externalDisplayManager.triggerSyncPass()
            updateChromeSample()
        }
        .onChange(of: browserState.isLoading) { isLoading in
            guard isLoading else { return }
            guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
            serverState.handlerContext.mark3DInspectorInactive(notify: false)
            isIn3DInspector = false
            inspectorMode = "rotate"
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                serverState: serverState,
                onShowWelcome: presentWelcomeFromHelp,
                onNavigate: { url in
                    navigate(url)
                }
            )
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
        .sheet(isPresented: $showAI) {
            AIStatusView()
        }
        .onChange(of: serverState.activePanel) { panel in
            guard let panel else { return }
            serverState.activePanel = nil
            // Dismiss any open sheet first
            showHistory = false
            showBookmarks = false
            showNetworkInspector = false
            showSettings = false
            showAI = false
            // Delay to let SwiftUI dismiss, then present the new sheet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                switch panel {
                case "history": showHistory = true
                case "bookmarks": showBookmarks = true
                case "network-inspector": showNetworkInspector = true
                case "settings": showSettings = true
                case "ai": showAI = true
                default: break
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWelcomeCard)) { _ in
            welcomePresentationSource = .helpMenu
            showWelcome = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .snapshot3DExited)) { _ in
            isIn3DInspector = false
            inspectorMode = "rotate"
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectViewportPreset)) { notification in
            guard isPad else { return }
            let presetID = notification.userInfo?["presetId"] as? String ?? ""
            guard presetID.isEmpty || availableIPadViewportPresetIDs.contains(presetID) else { return }
            setTabletViewportPreset(presetID)
        }
        .onChange(of: serverState.isScriptRecording) { isRecording in
            guard isRecording else { return }
            showSettings = false
            showBookmarks = false
            showHistory = false
            showNetworkInspector = false
            showAI = false
            showTabOverview = false
            showWelcome = false
            touchpadMode = false
        }
    }

    var shouldShowWelcomeCard: Bool {
        switch welcomePresentationSource {
        case .automatic:
            return !hideWelcome
        case .helpMenu:
            return true
        }
    }

    var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    func navigate(_ urlString: String) {
        tabStore.activeBrowserTab?.isStartPage = false
        guard let webView = browserState.webView, let url = URL(string: urlString) else { return }
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        browserState.webView?.goBack()
    }

    func goForward() {
        browserState.webView?.goForward()
    }

    func reload() {
        browserState.webView?.reload()
    }

    func authenticateInSafari() {
        guard let webView = browserState.webView, let url = webView.url else { return }
        Task { @MainActor in
            do {
                try await safariAuth.authenticate(url: url, webView: webView)
            } catch SafariAuthError.session(let underlying) {
                await serverState.handlerContext.showToast("Safari sign-in failed: \(underlying.localizedDescription)")
            } catch SafariAuthError.webViewUnavailable {
                await serverState.handlerContext.showToast("Safari sign-in cancelled: tab closed")
            } catch {
                await serverState.handlerContext.showToast("Safari sign-in failed: \(error.localizedDescription)")
            }
        }
    }

}
