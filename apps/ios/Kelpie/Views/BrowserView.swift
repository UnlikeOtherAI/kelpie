// swiftlint:disable file_length
import SwiftUI
import WebKit

let ipadMobileStagePresetDefaultsKey = "ipadMobileStagePreset"
let ipadMobileStageAvailablePresetIDsDefaultsKey = "ipadMobileStageAvailablePresetIDs"
let ipadMobileStageAvailableWidthDefaultsKey = "ipadMobileStageAvailableWidth"
let ipadMobileStageAvailableHeightDefaultsKey = "ipadMobileStageAvailableHeight"
private let tabletViewportStagePadding: CGFloat = 24
private let tabletViewportStageTopChromeHeight: CGFloat = 48

private enum WelcomeCardPresentationSource {
    case automatic
    case helpMenu
}

struct TabletViewportPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let label: String
    let menuLabel: String
    let displaySizeLabel: String
    let pixelResolutionLabel: String
    let portraitSize: CGSize
}

private func _cstr(_ ptr: UnsafePointer<CChar>?) -> String {
    guard let ptr else { return "" }
    return String(cString: ptr)
}

private func viewportPresetSortValue(_ label: String) -> Double {
    let pattern = #"[0-9]+(?:\.[0-9]+)?"#
    guard let range = label.range(of: pattern, options: .regularExpression) else {
        return .greatestFiniteMagnitude
    }
    return Double(label[range]) ?? .greatestFiniteMagnitude
}

let tabletViewportPresets: [TabletViewportPreset] = {
    var result: [TabletViewportPreset] = []
    let count = Int(kelpie_viewport_preset_count())
    for i in 0 ..< count {
        guard let preset = kelpie_viewport_preset_get(Int32(i))?.pointee else { continue }
        result.append(TabletViewportPreset(
            id: _cstr(preset.id),
            name: _cstr(preset.name),
            label: _cstr(preset.label),
            menuLabel: _cstr(preset.menu_label),
            displaySizeLabel: _cstr(preset.display_size_label),
            pixelResolutionLabel: _cstr(preset.pixel_resolution_label),
            portraitSize: CGSize(width: CGFloat(preset.portrait_width), height: CGFloat(preset.portrait_height))
        ))
    }
    return result.sorted {
        let lhs = viewportPresetSortValue($0.displaySizeLabel)
        let rhs = viewportPresetSortValue($1.displaySizeLabel)
        if lhs != rhs { return lhs < rhs }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
}()

let defaultTabletViewportPresetID = "compact-base"

func tabletViewportPreset(id: String?) -> TabletViewportPreset? {
    guard let id else { return nil }
    return tabletViewportPresets.first { $0.id == id }
}

func currentTabletViewportAvailableSize() -> CGSize {
    let defaults = UserDefaults.standard
    return CGSize(
        width: defaults.double(forKey: ipadMobileStageAvailableWidthDefaultsKey),
        height: defaults.double(forKey: ipadMobileStageAvailableHeightDefaultsKey)
    )
}

func currentTabletViewportAvailablePresetIDs() -> [String] {
    let raw = UserDefaults.standard.string(forKey: ipadMobileStageAvailablePresetIDsDefaultsKey) ?? ""
    return raw.split(separator: ",").map(String.init)
}

func orientedTabletViewportSize(for preset: TabletViewportPreset, availableSize: CGSize) -> CGSize {
    guard availableSize.width > availableSize.height else { return preset.portraitSize }
    return CGSize(width: preset.portraitSize.height, height: preset.portraitSize.width)
}

func fittingTabletViewportPresets(for availableSize: CGSize) -> [TabletViewportPreset] {
    let maxWidth = max(availableSize.width - tabletViewportStagePadding * 2, 1)
    let maxHeight = max(availableSize.height - tabletViewportStagePadding * 2 - tabletViewportStageTopChromeHeight, 1)

    return tabletViewportPresets.filter { preset in
        let targetViewport = orientedTabletViewportSize(for: preset, availableSize: availableSize)
        return targetViewport.width <= maxWidth && targetViewport.height <= maxHeight
    }
}

func tabletViewportSize(for preset: TabletViewportPreset, availableSize: CGSize) -> CGSize {
    let targetViewport = orientedTabletViewportSize(for: preset, availableSize: availableSize)
    let maxWidth = max(availableSize.width - tabletViewportStagePadding * 2, 1)
    let maxHeight = max(availableSize.height - tabletViewportStagePadding * 2 - tabletViewportStageTopChromeHeight, 1)

    return CGSize(
        width: min(targetViewport.width, maxWidth),
        height: min(targetViewport.height, maxHeight)
    )
}

/// Main browser screen: URL bar + WKWebView + floating action menu.
struct BrowserView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var serverState: ServerState
    @ObservedObject private var externalDisplayManager = ExternalDisplayManager.shared
    @AppStorage("ipadMobileStageEnabled") private var legacyIPadMobileStageEnabled = false
    @AppStorage(ipadMobileStagePresetDefaultsKey) private var iPadMobileStagePresetID = ""
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var showHistory = false
    @State private var showNetworkInspector = false
    @State private var showAI = false
    @State private var availableIPadViewportPresetIDs: [String] = []
    @AppStorage("hideWelcomeCard") private var hideWelcome = false
    @State private var showWelcome = true
    @State private var welcomePresentationSource: WelcomeCardPresentationSource = .automatic
    @AppStorage("debugOverlay") private var debugOverlayEnabled = false
    @State private var debugText = ""
    @State private var isIn3DInspector = false
    @State private var inspectorMode = "rotate"
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
                if browserState.isLoading && !serverState.isScriptRecording {
                    ProgressView(value: browserState.progress)
                        .progressViewStyle(.linear)
                }

                if !serverState.isScriptRecording {
                    URLBarView(
                        browserState: browserState,
                        onNavigate: navigate,
                        onBack: goBack,
                        onForward: goForward,
                        showAI: AIState.shared.isAvailable,
                        onAI: { showAI = true },
                        onSnapshot3D: {
                            Task { @MainActor in
                                await toggle3DInspector()
                            }
                        }
                    )
                }

                browserViewport
            }

            if showWelcome && shouldShowWelcomeCard {
                WelcomeCardView {
                    showWelcome = false
                    welcomePresentationSource = .automatic
                }
                    .transition(.opacity)
                    .zIndex(10)
            }

            if !serverState.isScriptRecording {
                FloatingMenuView(
                    onReload: reload,
                    onSafariAuth: authenticateInSafari,
                    onSettings: { showSettings = true },
                    onBookmarks: { showBookmarks = true },
                    onHistory: { showHistory = true },
                    onNetworkInspector: { showNetworkInspector = true },
                    onAI: { showAI = true },
                    onSnapshot3D: {
                        Task { @MainActor in
                            await toggle3DInspector()
                        }
                    },
                    show3DInspector: FeatureFlags.is3DInspectorEnabled,
                    showMobileViewportToggle: isPad,
                    mobileViewportPresets: availableTabletViewportPresetOptions,
                    selectedMobileViewportPresetID: activeTabletViewportPreset?.id,
                    onSelectMobileViewportPreset: toggleTabletViewportPreset,
                    side: $fabSide
                )
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
        .ignoresSafeArea(.container, edges: serverState.isScriptRecording ? [.top, .bottom] : .bottom)
        .statusBarHidden(serverState.isScriptRecording)
        .onChange(of: browserState.currentURL) { newURL in
            HistoryStore.shared.record(url: newURL, title: browserState.pageTitle)
            externalDisplayManager.triggerSyncPass()
        }
        .onChange(of: browserState.pageTitle) { newTitle in
            HistoryStore.shared.updateLatestTitle(for: browserState.currentURL, title: newTitle)
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
            showWelcome = false
            touchpadMode = false
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

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    @ViewBuilder
    private var browserViewport: some View {
        GeometryReader { geometry in
            let availablePresets = fittingTabletViewportPresets(for: geometry.size)
            let selectedPreset = availablePresets.first { $0.id == iPadMobileStagePresetID }
            let mobileStageActive = isPad && selectedPreset != nil
            let stageSize = selectedPreset.map { tabletViewportSize(for: $0, availableSize: geometry.size) } ?? geometry.size

            ZStack {
                if mobileStageActive {
                    Color(uiColor: .systemGray5)
                        .ignoresSafeArea(.container, edges: .bottom)
                }

                if let selectedPreset {
                    stagedWebViewContainer(
                        preset: selectedPreset,
                        stageSize: stageSize
                    )
                    .allowsHitTesting(!serverState.isScriptRecording)
                } else {
                    webViewContainer
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(!serverState.isScriptRecording)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.18), value: mobileStageActive)
            .animation(.easeOut(duration: 0.18), value: geometry.size)
            .onAppear { updateAvailableTabletViewportPresetState(for: geometry.size) }
            .onChange(of: geometry.size) { size in
                updateAvailableTabletViewportPresetState(for: size)
            }
        }
    }

    private func presentWelcomeFromHelp() {
        showSettings = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            welcomePresentationSource = .helpMenu
            showWelcome = true
        }
    }

    private var webViewContainer: some View {
        WebViewContainer(browserState: browserState, handlerContext: serverState.handlerContext) { wv in
            browserState.webView = wv
            serverState.webView = wv
            serverState.handlerContext.webView = wv
            externalDisplayManager.setPhoneWebView(wv)
        }
    }

    @ViewBuilder
    private func stagedWebViewContainer(preset: TabletViewportPreset, stageSize: CGSize) -> some View {
        if serverState.isScriptRecording {
            webViewContainer
                .frame(width: stageSize.width, height: stageSize.height)
        } else {
            VStack(spacing: 10) {
                ZStack {
                    Text(stageSummary(for: preset))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.9))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.9), lineWidth: 1)
                        }
                        .accessibilityIdentifier("browser.viewport.summary")
                }
                .frame(width: stageSize.width, height: 38)
                .overlay(alignment: .leading) {
                    Button {
                        setTabletViewportPreset("")
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.9))
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
                            }
                    }
                    .accessibilityIdentifier("browser.viewport.close")
                }

                webViewContainer
                    .frame(width: stageSize.width, height: stageSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.7), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            }
            .frame(width: stageSize.width, height: stageSize.height + tabletViewportStageTopChromeHeight)
        }
    }

    private var activeTabletViewportPreset: TabletViewportPreset? {
        guard isPad else { return nil }
        return tabletViewportPresets
            .first { availableIPadViewportPresetIDs.contains($0.id) && $0.id == iPadMobileStagePresetID }
    }

    private var availableTabletViewportPresetOptions: [MobileViewportPresetOption] {
        tabletViewportPresets
            .filter { availableIPadViewportPresetIDs.contains($0.id) }
            .map { MobileViewportPresetOption(id: $0.id, label: $0.menuLabel) }
    }

    private func toggleTabletViewportPreset(_ presetID: String) {
        setTabletViewportPreset((iPadMobileStagePresetID == presetID) ? "" : presetID)
    }

    private func stageSummary(for preset: TabletViewportPreset) -> String {
        "\(preset.displaySizeLabel) • \(preset.pixelResolutionLabel)"
    }

    private func migrateLegacyTabletViewportSelectionIfNeeded() {
        guard isPad else { return }
        guard iPadMobileStagePresetID.isEmpty, legacyIPadMobileStageEnabled else { return }
        setTabletViewportPreset(defaultTabletViewportPresetID)
        legacyIPadMobileStageEnabled = false
    }

    private func updateAvailableTabletViewportPresetState(for availableSize: CGSize) {
        let nextIDs = fittingTabletViewportPresets(for: availableSize).map(\.id)
        UserDefaults.standard.set(nextIDs.joined(separator: ","), forKey: ipadMobileStageAvailablePresetIDsDefaultsKey)
        UserDefaults.standard.set(availableSize.width, forKey: ipadMobileStageAvailableWidthDefaultsKey)
        UserDefaults.standard.set(availableSize.height, forKey: ipadMobileStageAvailableHeightDefaultsKey)

        if nextIDs != availableIPadViewportPresetIDs {
            availableIPadViewportPresetIDs = nextIDs
        }

        if !iPadMobileStagePresetID.isEmpty, !nextIDs.contains(iPadMobileStagePresetID) {
            setTabletViewportPreset("")
        }
    }

    private func setTabletViewportPreset(_ presetID: String) {
        iPadMobileStagePresetID = presetID
        UserDefaults.standard.set(presetID, forKey: ipadMobileStagePresetDefaultsKey)
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

    @MainActor
    private func toggle3DInspector() async {
        if serverState.handlerContext.isIn3DInspector || isIn3DInspector {
            await exit3DInspector()
            return
        }

        _ = try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.enterScript)
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
        _ = try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.exitScript)
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
        let connectedScreens = UIApplication.shared.connectedScenes.compactMap { scene in
            (scene as? UIWindowScene)?.screen
        }
        var screensByID: [ObjectIdentifier: UIScreen] = [:]
        for screen in connectedScreens + [UIScreen.main] {
            screensByID[ObjectIdentifier(screen)] = screen
        }
        let screens = Array(screensByID.values)
        let mgr = ExternalDisplayManager.shared
        var lines: [String] = []

        for (i, screen) in screens.enumerated() {
            let origin = screen.bounds.origin
            let wx = Int(origin.x), wy = Int(origin.y)
            let ww = Int(screen.bounds.width), wh = Int(screen.bounds.height)
            let sc = Int(screen.scale), nat = Int(screen.nativeScale)
            lines.append("scr[\(i)] \(wx),\(wy) \(ww)x\(wh) @\(sc)x nat=\(nat)x mir=\(screen.mirrored != nil)")
        }

        lines.append("ext: \(mgr.isConnected ? "ON" : "off") sync=\(mgr.isSyncEnabled)")

        if let win = mgr.externalWindow {
            let wf = win.frame
            lines.append("win: \(Int(wf.width))x\(Int(wf.height))")
        }
        if let wv = mgr.serverState?.handlerContext.webView {
            let bounds = wv.bounds
            lines.append("wv: \(Int(bounds.width))x\(Int(bounds.height)) csf=\(String(format: "%.0f", wv.contentScaleFactor))")
        }

        lines.append("phone: port \(serverState.deviceInfo.port)")
        debugText = lines.joined(separator: "\n")
    }
}
