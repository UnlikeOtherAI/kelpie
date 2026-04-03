import SwiftUI

/// Main browser window: toolbar + renderer view + floating menu overlay.
struct BrowserView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var serverState: ServerState
    @ObservedObject var rendererState: RendererState
    @ObservedObject var viewportState: ViewportState
    @ObservedObject private var aiState = AIState.shared
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var showHistory = false
    @State private var showNetworkInspector = false
    @StateObject private var aiChatSession = AIChatSession()
    @State private var isAIPanelOpen: Bool = UserDefaults.standard.bool(forKey: "com.mollotov.macos.ai-panel-open")
    @State private var aiPanelTab: AIPanelTab = .models
    @State private var aiPanelWidth: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "com.mollotov.macos.ai-panel-width")
        return CGFloat(v >= 200 ? v : 250)
    }()
    @State private var isFloatingMenuOpen = false
    @State private var isIn3DInspector = false
    @State private var inspectorMode = "rotate"
    @AppStorage("hideWelcomeCard") private var hideWelcome = false
    @State private var showWelcome = true
    @State private var welcomePresentationSource: WelcomeCardPresentationSource = .automatic

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // URL bar — fixed height, never compressed
                URLBarView(
                    browserState: browserState,
                    rendererState: rendererState,
                    viewportState: viewportState,
                    aiState: aiState,
                    isAIPanelOpen: isAIPanelOpen,
                    onNavigate: { url in
                        guard let urlObj = URL(string: url) else { return }
                        serverState.handlerContext.load(url: urlObj)
                    },
                    onBack: { serverState.handlerContext.goBack() },
                    onForward: { serverState.handlerContext.goForward() },
                    onReload: { serverState.handlerContext.reloadPage() },
                    onAIToggle: handleAIPillTap,
                    onSnapshot3D: {
                        Task { @MainActor in
                            await toggle3DInspector()
                        }
                    },
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

                HStack(spacing: 0) {
                    rendererSurface

                    if isAIPanelOpen {
                        AIPanelResizeHandle(panelWidth: $aiPanelWidth, onDragEnd: persistAIPanelWidth)
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

            if browserState.isLoading {
                FloatingProgressPill(progress: browserState.progress)
                    .zIndex(10)
            }

            if isFloatingMenuOpen {
                WindowBlurOverlay(opacity: 0.5)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

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
            .padding(.trailing, isAIPanelOpen ? aiPanelWidth + 7 : 0)
            .animation(.easeOut(duration: 0.2), value: isAIPanelOpen)

            if let message = serverState.shellToastMessage {
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
        .onChange(of: browserState.currentURL) { _, newURL in
            HistoryStore.shared.record(url: newURL, title: browserState.pageTitle)
            aiChatSession.reset()
            Task { @MainActor in
                await serverState.handlerContext.persistRendererCookiesToSharedJar()
            }
        }
        .onChange(of: browserState.pageTitle) { _, newTitle in
            HistoryStore.shared.updateLatestTitle(for: browserState.currentURL, title: newTitle)
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
            BrowserCommandBridge(
                actions: BrowserCommandActions(
                    hardReload: { serverState.handlerContext.hardReloadPage() }
                )
            )
            .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $showSettings) {
            SettingsView(serverState: serverState, rendererState: rendererState)
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
        .onAppear {
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
            UserDefaults.standard.set(open, forKey: "com.mollotov.macos.ai-panel-open")
            guard let window = NSApp.keyWindow else { return }
            let panelTotal = aiPanelWidth + 6
            var frame = window.frame
            if open {
                frame.size.width += panelTotal
            } else {
                frame.size.width -= panelTotal
                frame.size.width = max(frame.size.width, ViewportState.minimumShellSize.width)
            }
            window.setFrame(frame, display: true, animate: false)
        }
    }

    private var shouldShowWelcomeCard: Bool {
        switch welcomePresentationSource {
        case .automatic:
            return !hideWelcome
        case .helpMenu:
            return true
        }
    }

    private var windowTitle: String {
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
    private func connectRendererState() async {
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
    private func sync(browserState: BrowserState, from renderer: any RendererEngine) {
        browserState.currentURL = renderer.currentURL?.absoluteString ?? ""
        browserState.pageTitle = renderer.currentTitle
        browserState.isLoading = renderer.isLoading
        browserState.canGoBack = renderer.canGoBack
        browserState.canGoForward = renderer.canGoForward
        browserState.progress = renderer.estimatedProgress
    }

    private func navigate(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        serverState.handlerContext.load(url: url)
    }

    private func openAIFromMenu() {
        aiPanelTab = aiState.activeModel == nil ? .models : .chat
        isAIPanelOpen = true
    }

    private func handleAIPillTap() {
        if isAIPanelOpen {
            isAIPanelOpen = false
            return
        }
        openAIFromMenu()
    }

    private func persistAIPanelWidth() {
        UserDefaults.standard.set(Double(aiPanelWidth), forKey: "com.mollotov.macos.ai-panel-width")
    }

    private func notifyRendererViewportChangeIfNeeded() {
        guard rendererState.activeEngine == .chromium else { return }
        guard viewportState.showsViewportStageChrome else { return }
        serverState.handlerContext.renderer?.viewportDidChange()
    }

    @MainActor
    private func toggle3DInspector() async {
        if serverState.handlerContext.isIn3DInspector || isIn3DInspector {
            await exit3DInspector()
            return
        }

        try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.enterScript)
        let active = try? await serverState.handlerContext.evaluateJSReturningString("!!window.__m3d")
        guard active == "true" else { return }

        serverState.handlerContext.isIn3DInspector = true
        isIn3DInspector = true
        inspectorMode = "rotate"
        _ = try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.setModeScript(inspectorMode))
    }

    @MainActor
    private func exit3DInspector() async {
        guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
        try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.exitScript)
        serverState.handlerContext.mark3DInspectorInactive(notify: true)
        isIn3DInspector = false
        inspectorMode = "rotate"
    }

    @MainActor
    private func set3DInspectorMode(_ mode: String) async {
        guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
        let normalized = mode == "scroll" ? "scroll" : "rotate"
        _ = try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.setModeScript(normalized))
        inspectorMode = normalized
    }

    @MainActor
    private func zoom3DInspector(by delta: Double) async {
        guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
        _ = try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.zoomByScript(delta))
    }

    @MainActor
    private func reset3DInspectorView() async {
        guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
        _ = try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.resetViewScript)
    }

    @ViewBuilder
    private var rendererSurface: some View {
        ViewportStageView(
            viewportState: viewportState,
            stageScale: rendererState.activeEngine == .chromium ? 1.0 : viewportState.scale
        ) {
            ZStack {
                RendererContainerView(serverState: serverState, rendererState: rendererState)

                if rendererState.isSwitching {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()

                    ProgressView("Switching renderer...")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}

private struct ViewportStageView<Content: View>: View {
    @ObservedObject var viewportState: ViewportState
    let stageScale: Double
    let content: () -> Content

    private let stageColor = Color(nsColor: NSColor(calibratedWhite: 0.17, alpha: 1))
    private let viewportBorderColor = Color(nsColor: NSColor(calibratedWhite: 0.42, alpha: 1))

    init(
        viewportState: ViewportState,
        stageScale: Double,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.viewportState = viewportState
        self.stageScale = stageScale
        self.content = content
    }

    // Height of the stage-chrome header (summary pill + spacing below it).
    private static var stageChromeHeight: CGFloat { 48 }

    var body: some View {
        GeometryReader { geometry in
            let vp     = viewportState.viewportSize
            let chrome = viewportState.showsViewportStageChrome
            // Scale only applies in preset/custom mode — Full always fills the stage.
            let scale  = chrome ? stageScale : 1.0

            // Visual size of the viewport after applying scale.
            let scaledW = (vp.width  * scale).rounded(.down)
            let scaledH = (vp.height * scale).rounded(.down)
            let chromeH: CGFloat = chrome ? (Self.stageChromeHeight + 10) : 0

            let canvasSize = CGSize(
                width:  max(scaledW, geometry.size.width),
                height: max(scaledH + chromeH, geometry.size.height)
            )

            ZStack {
                backgroundColor

                if vp.width > 0, vp.height > 0 {
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        ZStack {
                            Color.clear.frame(width: canvasSize.width, height: canvasSize.height)

                            VStack(spacing: chrome ? 10 : 0) {
                                if chrome {
                                    stageChromeHeader(width: scaledW)
                                }

                                // Render content at the logical viewport size, then scale visually.
                                // Negative padding adjusts the layout frame to match the visual size
                                // so the scroll view sees the correct content bounds.
                                content()
                                    .frame(width: vp.width, height: vp.height)
                                    .scaleEffect(scale, anchor: .center)
                                    .padding(.horizontal, -(vp.width  * (1 - scale)) / 2)
                                    .padding(.vertical,   -(vp.height * (1 - scale)) / 2)
                                    .background(Color.black)
                                    .clipShape(RoundedRectangle(cornerRadius: chrome ? 16 : 0, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: chrome ? 16 : 0, style: .continuous)
                                            .stroke(chrome ? viewportBorderColor : .clear, lineWidth: 1)
                                    )
                                    .shadow(color: chrome ? Color.black.opacity(0.22) : .clear, radius: 14, y: 6)
                            }
                        }
                        .frame(width: canvasSize.width, height: canvasSize.height)
                    }
                    .defaultScrollAnchor(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                viewportState.updateStageSize(geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                viewportState.updateStageSize(newSize)
            }
        }
    }

    private var backgroundColor: Color {
        viewportState.showsViewportStageChrome ? stageColor : Color(nsColor: .windowBackgroundColor)
    }

    @ViewBuilder
    private func stageChromeHeader(width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Button {
                _ = viewportState.selectFullViewport()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.9))
                    .clipShape(Circle())
                    .overlay { Circle().stroke(Color.white.opacity(0.9), lineWidth: 1) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("browser.viewport.close")

            Text(viewportState.stageSummaryLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.9))
                .clipShape(Capsule())
                .overlay { Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1) }
                .accessibilityIdentifier("browser.viewport.summary")

            // Balance spacer matching the close button width
            Color.clear.frame(width: 28, height: 28)
        }
        .frame(width: max(width, 80), height: Self.stageChromeHeight)
    }
}

private struct WindowChromeBridge: NSViewRepresentable {
    let title: String
    let minimumWindowSize: NSSize

    let resolutionLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        PassThroughNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.minSize = minimumWindowSize
            window.titleVisibility = .visible
            context.coordinator.attachWindowIfNeeded(window, minimumWindowSize: minimumWindowSize)

            if window.frame.width < minimumWindowSize.width || window.frame.height < minimumWindowSize.height {
                var frame = window.frame
                let targetWidth = max(frame.width, minimumWindowSize.width)
                let targetHeight = max(frame.height, minimumWindowSize.height)
                let widthDelta = targetWidth - frame.width

                frame.size.width = targetWidth
                frame.size.height = targetHeight
                frame.origin.x -= widthDelta / 2
                window.setFrame(frame, display: true)
            }

            if window.title != title {
                window.title = title
            }

            context.coordinator.attachAccessoryIfNeeded(to: window)
            context.coordinator.updateResolutionLabel(resolutionLabel)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var observedWindow: NSWindow?
        private weak var accessoryWindow: NSWindow?
        private var resizeObserver: NSObjectProtocol?
        private let accessoryController = ResolutionTitlebarAccessoryController()

        deinit {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
        }

        func attachWindowIfNeeded(_ window: NSWindow, minimumWindowSize: NSSize) {
            guard observedWindow !== window else { return }

            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }

            observedWindow = window
            restoreWindowSizeIfAvailable(window, minimumWindowSize: minimumWindowSize)
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { _ in
                guard !window.styleMask.contains(.fullScreen) else { return }
                let contentSize = window.contentRect(forFrameRect: window.frame).size
                ViewportState.persistShellWindowSize(contentSize)
            }
        }

        func attachAccessoryIfNeeded(to window: NSWindow) {
            guard accessoryWindow !== window else { return }

            if accessoryController.parent == nil {
                accessoryController.layoutAttribute = .right
                window.addTitlebarAccessoryViewController(accessoryController)
            }

            accessoryWindow = window
        }

        func updateResolutionLabel(_ label: String) {
            accessoryController.setLabel(label)
        }

        private func restoreWindowSizeIfAvailable(_ window: NSWindow, minimumWindowSize: NSSize) {
            guard let savedSize = ViewportState.persistedShellWindowSize else { return }

            let targetSize = NSSize(
                width: max(savedSize.width, minimumWindowSize.width),
                height: max(savedSize.height, minimumWindowSize.height)
            )

            guard !sizesMatch(window.contentRect(forFrameRect: window.frame).size, targetSize) else { return }

            window.setContentSize(targetSize)
        }

        private func sizesMatch(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
            abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
        }
    }
}

private final class PassThroughNSView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct FloatingProgressPill: View {
    let progress: Double

    var body: some View {
        VStack {
            Spacer()
            GeometryReader { geometry in
                let pillWidth = geometry.size.width * 0.7

                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.45))
                    .frame(width: pillWidth, height: 6)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor)
                            .frame(
                                width: pillWidth * max(progress, 0.02),
                                height: 6
                            ),
                        alignment: .leading
                    )
                    .clipShape(Capsule(style: .continuous))
                    .frame(width: geometry.size.width)
            }
            .frame(height: 6)
            .padding(.bottom, 44)
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: progress)
    }
}

private struct WindowBlurOverlay: NSViewRepresentable {
    let opacity: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .withinWindow
        view.state = .active
        view.alphaValue = opacity
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.alphaValue = opacity
    }
}

private struct AIPanelResizeHandle: View {
    @Binding var panelWidth: CGFloat
    let onDragEnd: () -> Void

    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .padding(.horizontal, 2.5)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = panelWidth
                        }
                        guard let startWidth = dragStartWidth else { return }
                        let proposed = startWidth - value.translation.width
                        let newWidth = min(max(proposed, 200), 500)
                        if let window = NSApp.keyWindow {
                            let delta = newWidth - panelWidth
                            if abs(delta) > 0.5 {
                                var frame = window.frame
                                frame.size.width += delta
                                window.setFrame(frame, display: true)
                            }
                        }
                        panelWidth = newWidth
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        onDragEnd()
                    }
            )
    }
}

private final class ResolutionTitlebarAccessoryController: NSTitlebarAccessoryViewController {
    private let hostingView = NSHostingView(rootView: ResolutionTitlebarBadge(label: ""))

    override func loadView() {
        view = hostingView
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    func setLabel(_ label: String) {
        hostingView.rootView = ResolutionTitlebarBadge(label: label)
        hostingView.layoutSubtreeIfNeeded()
    }
}

private struct ResolutionTitlebarBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .accessibilityIdentifier("browser.viewport.resolution")
            .fixedSize()
    }
}

/// Wraps the active renderer's NSView in SwiftUI.
struct RendererContainerView: NSViewRepresentable {
    @ObservedObject var serverState: ServerState
    @ObservedObject var rendererState: RendererState

    final class Coordinator {
        var attachedEngine: RendererState.Engine?
        weak var attachedView: NSView?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        attachActiveRenderer(to: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        attachActiveRenderer(to: container, coordinator: context.coordinator)
    }

    private func attachActiveRenderer(to container: NSView, coordinator: Coordinator) {
        guard let activeView = serverState.handlerContext.renderer?.makeView() else {
            container.subviews.forEach { $0.isHidden = true }
            coordinator.attachedEngine = nil
            return
        }

        activeView.frame = container.bounds
        activeView.autoresizingMask = [.width, .height]

        // Add the view if it isn't already a subview.
        // We NEVER remove renderer views from the hierarchy — removing and
        // re-adding CEF's NSView corrupts its internal compositing state and
        // causes a CrBrowserMain crash. Use isHidden to switch instead.
        if activeView.superview !== container {
            container.addSubview(activeView)
        }

        // Show the active view, hide all others.
        for subview in container.subviews {
            subview.isHidden = subview !== activeView
        }

        coordinator.attachedEngine = rendererState.activeEngine
    }
}
