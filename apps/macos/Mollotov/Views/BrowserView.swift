import SwiftUI

/// Main browser window: toolbar + renderer view + floating menu overlay.
struct BrowserView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var serverState: ServerState
    @ObservedObject var rendererState: RendererState
    @ObservedObject var viewportState: ViewportState
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var showHistory = false
    @State private var showNetworkInspector = false
    @State private var isFloatingMenuOpen = false
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
                    onNavigate: { url in
                        guard let urlObj = URL(string: url) else { return }
                        serverState.handlerContext.load(url: urlObj)
                    },
                    onBack: { serverState.handlerContext.goBack() },
                    onForward: { serverState.handlerContext.goForward() },
                    onReload: { serverState.handlerContext.reloadPage() },
                    onSwitchRenderer: { engine in
                        Task {
                            await serverState.switchRenderer(to: engine)
                        }
                    }
                )
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

                rendererSurface
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
                onNetworkInspector: { showNetworkInspector = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

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
            Task { @MainActor in
                await serverState.handlerContext.persistRendererCookiesToSharedJar()
            }
        }
        .onChange(of: browserState.pageTitle) { _, newTitle in
            HistoryStore.shared.updateLatestTitle(for: browserState.currentURL, title: newTitle)
        }
        .animation(.easeOut(duration: 0.2), value: serverState.shellToastMessage != nil)
        .background(
            WindowChromeBridge(
                title: windowTitle,
                minimumWindowSize: viewportState.minimumWindowSize,
                resolutionLabel: viewportState.resolutionLabel
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
                await connectRendererState()
            }
        }
        .onChange(of: rendererState.activeEngine) { _, _ in
            Task { @MainActor in
                await connectRendererState()
            }
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

    @ViewBuilder
    private var rendererSurface: some View {
        Group {
            if rendererState.isSwitching {
                ViewportStageView(viewportState: viewportState) {
                    ProgressView("Switching renderer...")
                }
            } else {
                ViewportStageView(viewportState: viewportState) {
                    RendererContainerView(serverState: serverState, rendererState: rendererState)
                }
            }
        }
    }
}

private struct ViewportStageView<Content: View>: View {
    @ObservedObject var viewportState: ViewportState
    let content: () -> Content

    private let stageColor = Color(nsColor: NSColor(calibratedWhite: 0.17, alpha: 1))
    private let viewportBorderColor = Color(nsColor: NSColor(calibratedWhite: 0.42, alpha: 1))

    init(
        viewportState: ViewportState,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.viewportState = viewportState
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let viewportSize = viewportState.viewportSize
            let canvasSize = CGSize(
                width: max(viewportSize.width, geometry.size.width),
                height: max(viewportSize.height, geometry.size.height)
            )

            ZStack {
                backgroundColor

                if viewportSize.width > 0, viewportSize.height > 0 {
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        ZStack {
                            Color.clear
                                .frame(width: canvasSize.width, height: canvasSize.height)

                            content()
                                .frame(width: viewportSize.width, height: viewportSize.height)
                                .background(Color.black)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: viewportState.showsViewportStageChrome ? 16 : 0,
                                        style: .continuous
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: viewportState.showsViewportStageChrome ? 16 : 0,
                                        style: .continuous
                                    )
                                    .stroke(
                                        viewportState.showsViewportStageChrome ? viewportBorderColor : .clear,
                                        lineWidth: 1
                                    )
                                )
                                .shadow(
                                    color: viewportState.showsViewportStageChrome ? Color.black.opacity(0.22) : .clear,
                                    radius: 14,
                                    y: 6
                                )
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
        guard let view = serverState.handlerContext.renderer?.makeView() else {
            coordinator.attachedView?.removeFromSuperview()
            coordinator.attachedView = nil
            coordinator.attachedEngine = nil
            return
        }

        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]

        let needsSwap =
            coordinator.attachedEngine != rendererState.activeEngine ||
            coordinator.attachedView !== view ||
            view.superview !== container

        guard needsSwap else { return }

        if view.superview !== container {
            view.removeFromSuperview()
            container.subviews.forEach { $0.removeFromSuperview() }
            container.addSubview(view)
        }

        coordinator.attachedView = view
        coordinator.attachedEngine = rendererState.activeEngine
    }
}
