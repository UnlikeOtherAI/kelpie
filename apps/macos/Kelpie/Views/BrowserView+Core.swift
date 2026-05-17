import SwiftUI

extension BrowserView {
    var shouldShowWelcomeCard: Bool {
        switch welcomePresentationSource {
        case .automatic:
            return !hideWelcome
        case .helpMenu:
            return true
        }
    }

    var windowTitle: String {
        let trimmedTitle = browserState.pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        if let host = URL(string: browserState.currentURL)?.host, !host.isEmpty {
            return host
        }

        return "New Tab"
    }

    @MainActor
    func connectRendererState() async {
        // WebKit renderer state is managed per-tab by connectNewTab.
        // Only wire onStateChange for the Chromium renderer here.
        guard rendererState.activeEngine == .chromium else { return }

        for _ in 0..<10 {
            if let renderer = serverState.handlerContext.renderer {
                renderer.onStateChange = { [weak browserState, weak handlerContext = serverState.handlerContext] in
                    Task { @MainActor in
                        guard let browserState, let renderer = handlerContext?.renderer else { return }
                        sync(browserState: browserState, from: renderer)
                    }
                }
                sync(browserState: browserState, from: renderer)
                return
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @MainActor
    func sync(browserState: BrowserState, from renderer: any RendererEngine) {
        browserState.currentURL = renderer.currentURL?.absoluteString ?? ""
        browserState.pageTitle = renderer.currentTitle
        browserState.isLoading = renderer.isLoading
        browserState.canGoBack = renderer.canGoBack
        browserState.canGoForward = renderer.canGoForward
        browserState.progress = renderer.estimatedProgress
    }

    func connectNewTab(_ tab: Tab) {
        serverState.setActiveWebKitRenderer(tab.renderer)
        sync(browserState: browserState, from: tab.renderer)
        tab.renderer.onStateChange = { [weak tab, weak browserState, weak serverState] in
            guard let tab, let browserState, let serverState else { return }
            Task { @MainActor in
                // Update tab's own stored state (always, for all tabs — tab bar needs these)
                let wasLoading = tab.isLoading
                tab.title = tab.renderer.currentTitle.isEmpty ? "Start Page" : tab.renderer.currentTitle
                tab.currentURL = tab.renderer.currentURL?.absoluteString ?? ""
                tab.isLoading = tab.renderer.isLoading

                // Only sync shared browserState for the active tab
                guard serverState.wkRenderer === tab.renderer else { return }
                sync(browserState: browserState, from: tab.renderer)

                // Favicon fetch on load completion (active tab only)
                if wasLoading && !tab.isLoading, !tab.currentURL.isEmpty {
                    FaviconExtractor.extract(from: tab.renderer) { [weak tab] image in
                        tab?.favicon = image
                    }
                }
            }
        }
    }

    func activateTab(_ tab: Tab) {
        connectNewTab(tab)
    }

    /// Cmd+T handler. Routed per-window by `BrowserCommandRouter` so only the
    /// active window opens a new tab, never every window simultaneously.
    func handleNewTabCommand() {
        guard !serverState.isScriptRecording else { return }
        guard rendererState.activeEngine != .chromium else { return }
        let tab = tabStore.addTab()
        connectNewTab(tab)
    }

    /// Cmd+W handler. Routed per-window by `BrowserCommandRouter`. Closes the
    /// active tab on WebKit; closes the window itself when Chromium is active
    /// because Chromium tab management is single-tab today.
    func handleCloseTabCommand() {
        guard !serverState.isScriptRecording else { return }
        if rendererState.activeEngine == .chromium {
            NSApp.keyWindow?.close()
            return
        }
        guard let id = tabStore.activeTabID else { return }
        tabStore.closeTab(id: id)
        if let next = tabStore.activeTab { activateTab(next) }
    }

    func navigate(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        if url.scheme == "http" && !skipInsecureWarning {
            pendingInsecureURL = url
            return
        }
        serverState.handlerContext.load(url: url)
    }

    /// Installs this window's tab-mutation callbacks in `WindowRegistry` so
    /// HTTP handlers can drive new-tab/switch-tab/close-tab against the
    /// correct shell. The window pointer is registered separately by the
    /// `WindowRegistrationBridge` once SwiftUI attaches a hosting `NSWindow`.
    /// Safe to call repeatedly; later calls overwrite any stale callbacks.
    @MainActor
    func registerWindow() {
        // Ensure the entry exists even before the bridge fires so callbacks
        // can be installed immediately. The window reference is filled in by
        // the bridge when the NSWindow becomes available.
        WindowRegistry.shared.register(id: windowId, window: nil, tabStore: tabStore)
        WindowRegistry.shared.installCallbacks(
            for: windowId,
            callbacks: WindowRegistry.Callbacks(
                onNewTab: { [self] in
                    let tab = tabStore.addTab()
                    connectNewTab(tab)
                    return tab
                },
                onSwitchTab: { [self] id in
                    tabStore.selectTab(id: id)
                    if let tab = tabStore.activeTab {
                        activateTab(tab)
                    }
                },
                onCloseTab: { [self] id in
                    tabStore.closeTab(id: id)
                    if let tab = tabStore.activeTab {
                        activateTab(tab)
                    }
                },
                onWillLoad: { [weak tabStore] in
                    tabStore?.activeTab?.isStartPage = false
                }
            )
        )
    }

    func openAIFromMenu() {
        aiPanelTab = aiState.activeModel == nil ? .models : .chat
        isAIPanelOpen = true
    }

    func handleAIPillTap() {
        if isAIPanelOpen {
            isAIPanelOpen = false
            return
        }
        openAIFromMenu()
    }

    func persistAIPanelWidth() {
        UserDefaults.standard.set(Double(aiPanelWidth), forKey: "com.kelpie.macos.ai-panel-width")
    }

    func notifyRendererViewportChangeIfNeeded() {
        guard rendererState.activeEngine == .chromium else { return }
        guard viewportState.showsViewportStageChrome else { return }
        serverState.handlerContext.renderer?.viewportDidChange()
    }

    @ViewBuilder
    var rendererSurface: some View {
        ViewportStageView(
            viewportState: viewportState,
            stageScale: rendererState.activeEngine == .chromium ? 1.0 : viewportState.scale,
            showsStageChrome: !serverState.isScriptRecording && viewportState.showsViewportStageChrome
        ) {
            ZStack {
                RendererContainerView(serverState: serverState, rendererState: rendererState, tabStore: tabStore)

                // Start page overlay — shown when the active tab has no URL.
                // The WKWebView is hidden by RendererContainerView.updateNSView in
                // this state, so SwiftUI buttons here receive mouse events normally.
                if tabStore.activeTab?.isStartPage == true {
                    StartPageView(
                        bookmarkStore: .shared,
                        historyStore: .shared,
                        onNavigate: navigate
                    )
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: tabStore.activeTab?.isStartPage)
                }

                if rendererState.isSwitching {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()

                    ProgressView("Switching renderer...")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .allowsHitTesting(!serverState.isScriptRecording)
        }
    }
}
