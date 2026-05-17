import SwiftUI

/// Main browser window: toolbar + renderer view + floating menu overlay.
struct BrowserView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var serverState: ServerState
    @ObservedObject var rendererState: RendererState
    @ObservedObject var viewportState: ViewportState
    @ObservedObject var aiState = AIState.shared
    /// Each window owns its own tab list. The app-level `KelpieApp` does NOT
    /// inject a shared store — that was the source of the HTTP-routing bug
    /// where `tabId=X` in one window resolved against another window's tabs.
    @StateObject var tabStore = TabStore()
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var showHistory = false
    @State private var showNetworkInspector = false
    @StateObject private var aiChatSession = AIChatSession()
    @State var isAIPanelOpen: Bool = UserDefaults.standard.bool(forKey: "com.kelpie.macos.ai-panel-open")
    @State var aiPanelTab: AIPanelTab = .models
    @State var aiPanelWidth: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "com.kelpie.macos.ai-panel-width")
        return CGFloat(v >= 200 ? v : 250)
    }()
    @State private var isFloatingMenuOpen = false
    @State var isIn3DInspector = false
    @State var inspectorMode = "rotate"
    @AppStorage("hideWelcomeCard") var hideWelcome = false
    @State private var showWelcome = false
    @State var welcomePresentationSource: WelcomeCardPresentationSource = .automatic
    @AppStorage("skipInsecureWarning") var skipInsecureWarning = false
    @State var pendingInsecureURL: URL?
    /// Stable per-window id used by `WindowRegistry` so HTTP handlers can
    /// route `(windowId, tabId)` requests to the correct shell.
    @State var windowId: String = UUID().uuidString

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !serverState.isScriptRecording {
                    // URL bar — above all overlays so buttons are always clickable
                    URLBarView(
                        browserState: browserState,
                        rendererState: rendererState,
                        viewportState: viewportState,
                        aiState: aiState,
                        isAIPanelOpen: isAIPanelOpen,
                        onNavigate: navigate,
                        onBack: { serverState.handlerContext.goBack() },
                        onForward: { serverState.handlerContext.goForward() },
                        onReload: { serverState.handlerContext.reloadPage() },
                        onAIToggle: handleAIPillTap,
                        onSnapshot3D: {
                            Task { @MainActor in
                                await toggle3DInspector()
                            }
                        },
                        is3DActive: isIn3DInspector,
                        show3DControls: isIn3DInspector,
                        inspectorMode: inspectorMode,
                        onSetInspectorMode: { mode in
                            Task { @MainActor in
                                await set3DInspectorMode(mode)
                            }
                        },
                        onInspectorExit: {
                            Task { @MainActor in
                                await exit3DInspector()
                            }
                        },
                        onInspectorZoomIn: {
                            Task { @MainActor in
                                await zoom3DInspector(by: 0.12)
                            }
                        },
                        onInspectorZoomOut: {
                            Task { @MainActor in
                                await zoom3DInspector(by: -0.12)
                            }
                        },
                        onInspectorReset: {
                            Task { @MainActor in
                                await reset3DInspectorView()
                            }
                        },
                        onSwitchRenderer: { engine in
                            Task {
                                await serverState.switchRenderer(to: engine)
                            }
                        }
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                    TabBarView(
                        tabStore: tabStore,
                        onNewTab: {
                            let tab = tabStore.addTab()
                            connectNewTab(tab)
                        },
                        onCloseTab: { id in
                            let wasActive = tabStore.activeTabID == id
                            tabStore.closeTab(id: id)
                            if wasActive, let next = tabStore.activeTab { activateTab(next) }
                        },
                        onSelectTab: { id in
                            tabStore.selectTab(id: id)
                            if let tab = tabStore.activeTab { activateTab(tab) }
                        }
                    )
                    .frame(height: tabStore.tabs.count > 1 && rendererState.activeEngine != .chromium ? 34 : 0)
                    .opacity(tabStore.tabs.count > 1 && rendererState.activeEngine != .chromium ? 1 : 0)
                    .allowsHitTesting(tabStore.tabs.count > 1 && rendererState.activeEngine != .chromium)
                    .animation(.easeOut(duration: 0.3), value: tabStore.tabs.count > 1)
                    .animation(.easeOut(duration: 0.3), value: rendererState.activeEngine)
                }

                HStack(spacing: 0) {
                    // Renderer with overlays — FloatingMenuView only covers this area
                    ZStack {
                        rendererSurface

                        if browserState.isLoading {
                            FloatingProgressPill(progress: browserState.progress)
                                .zIndex(10)
                        }

                        if isFloatingMenuOpen && !serverState.isScriptRecording {
                            WindowBlurOverlay(opacity: 0.5)
                                .ignoresSafeArea()
                                .allowsHitTesting(false)
                        }

                        if !serverState.isScriptRecording {
                            FloatingMenuView(
                                isOpen: $isFloatingMenuOpen,
                                onReload: { serverState.handlerContext.reloadPage() },
                                onSafariAuth: {
                                    if let url = serverState.handlerContext.currentURL {
                                        let helper = SafariAuthHelper()
                                        helper.handlerContext = serverState.handlerContext
                                        helper.authenticate(url: url)
                                    }
                                },
                                onSettings: { showSettings = true },
                                onBookmarks: { showBookmarks = true },
                                onHistory: { showHistory = true },
                                onNetworkInspector: { showNetworkInspector = true },
                                onAI: openAIFromMenu,
                                onSnapshot3D: {
                                    Task { @MainActor in
                                        await toggle3DInspector()
                                    }
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        }

                        if let message = serverState.shellToastMessage, !serverState.isScriptRecording {
                            VStack {
                                Spacer()
                                ShellToastCardView(message: message)
                                    .padding(.bottom, 20)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                            .zIndex(20)
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
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .zIndex(30)
                        }
                    }

                    // AI panel — outside the overlay ZStack so buttons are always clickable
                    if isAIPanelOpen && !serverState.isScriptRecording {
                        AppKitResizeHandle(panelWidth: $aiPanelWidth, onDragEnd: persistAIPanelWidth)
                        AIChatPanel(
                            aiState: aiState,
                            session: aiChatSession,
                            selectedTab: $aiPanelTab,
                            onClose: { isAIPanelOpen = false }
                        )
                        .frame(width: aiPanelWidth)
                    }
                }
            }

            if showWelcome && shouldShowWelcomeCard {
                WelcomeCardView {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showWelcome = false
                        welcomePresentationSource = .automatic
                    }
                }
                .transition(.opacity)
                .zIndex(30)
            }
        }
        .onChange(of: browserState.currentURL) { _, _ in
            aiChatSession.reset()
            Task { @MainActor in
                await serverState.handlerContext.persistRendererCookiesToSharedJar()
            }
        }
        .onChange(of: browserState.isLoading) { _, isLoading in
            guard isLoading else { return }
            guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
            serverState.handlerContext.mark3DInspectorInactive(notify: false)
            isIn3DInspector = false
            inspectorMode = "rotate"
        }
        .animation(.easeOut(duration: 0.2), value: serverState.shellToastMessage != nil)
        .background(
            WindowChromeBridge(
                title: windowTitle,
                minimumWindowSize: NSSize(
                    width: viewportState.minimumWindowSize.width + (isAIPanelOpen ? 206 : 0),
                    height: viewportState.minimumWindowSize.height
                ),
                resolutionLabel: viewportState.resolutionLabel
            )
            .frame(width: 0, height: 0)
        )
        .background(
            WindowRegistrationBridge(windowId: windowId, tabStore: tabStore)
                .frame(width: 0, height: 0)
        )
        .background(
            BrowserCommandBridge(
                actions: BrowserCommandActions(
                    hardReload: { serverState.handlerContext.hardReloadPage() },
                    newTab: { handleNewTabCommand() },
                    closeTab: { handleCloseTabCommand() }
                )
            )
            .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $showSettings) {
            SettingsView(serverState: serverState, rendererState: rendererState, onNavigate: navigate)
        }
        .pairingDialog(coordinator: serverState.pairingCoordinator)
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
        .sheet(isPresented: Binding(
            get: { pendingInsecureURL != nil },
            set: { if !$0 { pendingInsecureURL = nil } }
        )) {
            if let url = pendingInsecureURL {
                InsecurePageWarningView(
                    url: url,
                    skipInFuture: $skipInsecureWarning,
                    onContinue: {
                        let targetURL = url
                        pendingInsecureURL = nil
                        serverState.handlerContext.load(url: targetURL)
                    },
                    onCancel: { pendingInsecureURL = nil }
                )
            }
        }
        .onAppear {
            if let activeTab = tabStore.activeTab {
                activateTab(activeTab)
            } else {
                connectNewTab(tabStore.tabs[0])
            }
            // Register this window with the registry and install its
            // tab-mutation callbacks so HTTP handlers can route per-window
            // requests here.
            registerWindow()
            // Remove focus from URL bar on launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApplication.shared.keyWindow?.makeFirstResponder(nil)
            }
            Task { @MainActor in
                aiState.configure(localServerPort: UInt16(serverState.deviceInfo.port))
                aiState.onAuthFailureNavigate = { [weak serverState] url in
                    serverState?.handlerContext.load(url: url)
                }
                await connectRendererState()
            }
        }
        .onDisappear {
            WindowRegistry.shared.unregister(id: windowId)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            SessionStore.save(tabs: tabStore.tabs, activeID: tabStore.activeTabID)
        }
        .onChange(of: rendererState.activeEngine) { _, _ in
            Task { @MainActor in
                await connectRendererState()
            }
        }
        .onChange(of: viewportState.resolutionLabel) { _, _ in
            notifyRendererViewportChangeIfNeeded()
        }
        .onChange(of: viewportState.showsViewportStageChrome) { _, _ in
            notifyRendererViewportChangeIfNeeded()
        }
        .onExitCommand {
            if showWelcome && shouldShowWelcomeCard {
                showWelcome = false
                welcomePresentationSource = .automatic
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWelcomeCard)) { notification in
            let source = WelcomeCardPresentationSource(
                rawValue: notification.object as? String ?? ""
            ) ?? .automatic
            withAnimation(.easeOut(duration: 0.18)) {
                welcomePresentationSource = source
                showWelcome = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .snapshot3DExited)) { _ in
            isIn3DInspector = false
            inspectorMode = "rotate"
        }
        .onChange(of: isAIPanelOpen) { _, open in
            UserDefaults.standard.set(open, forKey: "com.kelpie.macos.ai-panel-open")
        }
        .onChange(of: serverState.isScriptRecording) { _, isRecording in
            guard isRecording else { return }
            showSettings = false
            showBookmarks = false
            showHistory = false
            showNetworkInspector = false
            showWelcome = false
            pendingInsecureURL = nil
            isAIPanelOpen = false
            isFloatingMenuOpen = false
        }
    }
}
