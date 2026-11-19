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
    func sync(browserState: BrowserState, from renderer: any RendererEngine) {
        browserState.currentURL = renderer.currentURL?.absoluteString ?? ""
        browserState.pageTitle = renderer.currentTitle
        browserState.isLoading = renderer.isLoading
        browserState.canGoBack = renderer.canGoBack
        browserState.canGoForward = renderer.canGoForward
        browserState.progress = renderer.estimatedProgress
    }

    func connectNewTab(_ tab: Tab) {
        guard let renderer = tabStore.renderer(for: tab) else { return }
        if tabStore.engine == .webkit {
            serverState.setActiveWebKitRenderer(tab.renderer)
        } else {
            serverState.router.invalidateAllBrowserReferences()
            renderer.onScriptMessage = { [weak context = serverState.handlerContext, weak renderer] name, body in
                guard let context, context.renderer === renderer else { return }
                context.handleScriptMessage(name: name, body: body)
            }
        }
        sync(browserState: browserState, from: renderer)
        // This replaces the store's callback, so it hands the tab's own state,
        // history and screenshot work back to the store before syncing the
        // window.
        renderer.onStateChange = { [weak tab, weak tabStore, weak browserState, weak renderer] in
            guard let tab, let tabStore, let browserState, let renderer else { return }
            Task { @MainActor in
                guard tabStore.tabs.contains(where: { $0 === tab }),
                      tabStore.engine.rawValue == renderer.engineName else { return }
                // Update tab's own stored state (always, for all tabs — tab bar needs these)
                let wasLoading = tab.isLoading
                tabStore.rendererStateChanged(tab, from: renderer)

                // Each window's chrome follows its own active tab.
                guard tabStore.activeTab === tab, !tab.isStartPage else { return }
                sync(browserState: browserState, from: renderer)

                // Favicon fetch on load completion (active tab only)
                if wasLoading && !tab.isLoading, !tab.currentURL.isEmpty {
                    FaviconExtractor.extract(from: renderer) { [weak tab] image in
                        tab?.favicon = image
                    }
                }
            }
        }
    }

    func activateTab(_ tab: Tab) {
        hoveredLinkURL = ""
        isChromeCollapsed = false
        connectNewTab(tab)
    }

    /// Cmd+T handler. Routed per-window by `BrowserCommandRouter` so only the
    /// active window opens a new tab, never every window simultaneously.
    func handleNewTabCommand() {
        isChromeCollapsed = false
        guard !serverState.isScriptRecording, !rendererState.isSwitching else { return }
        let tab = tabStore.addTab()
        connectNewTab(tab)
        addressFocusRequested = true
    }

    /// Cmd+W handler. Routed per-window by `BrowserCommandRouter`. Closes the
    /// active tab and selects its neighbor in the same window.
    func handleCloseTabCommand() {
        guard !serverState.isScriptRecording, !rendererState.isSwitching else { return }
        guard let id = tabStore.activeTabID else { return }
        tabStore.closeTab(id: id)
        if let next = tabStore.activeTab { activateTab(next) }
    }

    func navigate(_ urlString: String) {
        isChromeCollapsed = false
        guard let url = URL(string: urlString) else { return }
        if url.scheme == "http" && !skipInsecureWarning {
            pendingInsecureURL = url
            return
        }
        serverState.handlerContext.load(url: url, windowId: windowId)
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
        let window = WindowRegistry.shared.entry(for: windowId)?.window
        WindowRegistry.shared.register(id: windowId, window: window, tabStore: tabStore, ownsWindowChrome: ownsWindowChrome)
        WindowRegistry.shared.installCallbacks(
            for: windowId,
            callbacks: WindowRegistry.Callbacks(
                onNewTab: { [self] spec in
                    let tab = tabStore.addTab(spec: spec)
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
                    isChromeCollapsed = false
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
        KelpieStorage.defaults.set(Double(aiPanelWidth), forKey: "com.kelpie.macos.ai-panel-width")
    }

    func notifyRendererViewportChangeIfNeeded() {
        guard rendererState.activeEngine == .chromium else { return }
        guard viewportState.showsViewportStageChrome else { return }
        tabStore.activeRenderer?.viewportDidChange()
    }

    @ViewBuilder
    var rendererSurface: some View {
        ViewportStageView(
            viewportState: viewportState,
            stageScale: rendererState.activeEngine == .chromium ? 1.0 : viewportState.scale,
            contentUnderlap: chromeUnderlap,
            showsStageChrome: !serverState.isScriptRecording && viewportState.showsViewportStageChrome
        ) {
            ZStack {
                RendererContainerView(
                    chromeAppearance: chromeAppearance,
                    rendererState: rendererState,
                    tabStore: tabStore,
                    chromeUnderlap: chromeUnderlap,
                    onHoverURL: { hoveredLinkURL = $0 },
                    onChromeScroll: { collapsed in
                        guard !serverState.isScriptRecording, tabStore.activeTab?.isStartPage != true else { return }
                        withAnimation(.easeOut(duration: 0.18)) { isChromeCollapsed = collapsed }
                    }
                )

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
