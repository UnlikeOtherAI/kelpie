import Foundation
import AppKit
import Network
import Darwin

/// Observable state for the HTTP server, mDNS, and renderer management.
@MainActor
final class ServerState: ObservableObject {
    @Published var isServerRunning = false
    @Published var isMDNSAdvertising = false
    @Published var ipAddress: String = "0.0.0.0"
    @Published var isScriptRecording = false
    @Published var shellToastMessage: String?
    @Published private(set) var deviceInfo: DeviceInfo
    let viewportState = ViewportState()

    let router = Router()
    let handlerContext = HandlerContext()
    let scriptPlaybackState = ScriptPlaybackState()

    /// The renderer state is supplied to `startHTTPServer(rendererState:)`.
    /// Optional only because the view-model is created before the view layer
    /// constructs `RendererState`. Once HTTP serving begins, it is guaranteed
    /// non-nil because `startHTTPServer` stores it before `registerHandlers()`.
    private(set) var rendererState: RendererState?

    // Renderers are created on first use and cached for instant switching
    var wkRenderer: WKWebViewRenderer?

    /// Called by BrowserView when the active tab changes so the tab's renderer
    /// becomes the target for all handlers.
    func setActiveWebKitRenderer(_ renderer: WKWebViewRenderer) {
        renderer.onScriptMessage = { [weak self] name, body in
            self?.handlerContext.handleScriptMessage(name: name, body: body)
        }
        wkRenderer = renderer
        handlerContext.renderer = renderer
    }
    private(set) var cefRenderer: CEFRenderer?

    private var httpServer: HTTPServer?
    private var toastDismissTask: Task<Void, Never>?
    private weak var scriptRecordingWindow: NSWindow?
    private var scriptRecordingWasFullscreen = false

    init(port: UInt16 = 8420) {
        self.deviceInfo = DeviceInfo.current(port: Int(port))
        self.ipAddress = Self.getLocalIPAddress()
    }

    /// Starts the HTTP server and binds the supplied renderer state into
    /// every handler that needs it. The renderer state must be supplied
    /// here (not as a separate property assignment) so handler registration
    /// can read it without force-unwrapping.
    func startHTTPServer(rendererState: RendererState) {
        self.rendererState = rendererState
        let preferredPort = UInt16(deviceInfo.port)
        let resolvedPort = Self.firstAvailablePort(startingAt: preferredPort)
        if Int(resolvedPort) != deviceInfo.port {
            print("[ServerState] Port \(preferredPort) in use, falling back to \(resolvedPort)")
            deviceInfo = DeviceInfo.current(port: Int(resolvedPort))
        }

        // Pre-initialize CEF so the Mach port rendezvous server is registered
        // in the clean startup run loop context. cef_initialize() installs
        // CFRunLoop observers that only work correctly when called from a
        // top-level event loop iteration (not from an HTTP handler async chain).
        // Browser creation is still deferred to the first Chromium switch.
        CEFRenderer.ensureCEFInitialized()

        // Start only the selected renderer (browser instance). CEF is
        // initialized above but no Chromium browser is created yet.
        let startEngine = rendererState.activeEngine
        let activeRenderer = renderer(for: startEngine)
        handlerContext.renderer = activeRenderer
        handlerContext.startSharedCookieSync()

        registerHandlers(rendererState: rendererState)
        let server: HTTPServer
        do {
            server = try HTTPServer(port: resolvedPort, router: router)
        } catch {
            print("[ServerState] Failed to construct HTTPServer for port \(resolvedPort): \(error)")
            isServerRunning = false
            isMDNSAdvertising = false
            return
        }
        server.onBonjourStateChange = { [weak self] isAdvertising in
            Task { @MainActor in
                self?.isMDNSAdvertising = isAdvertising
            }
        }
        server.onStateChange = { [weak self] isRunning in
            Task { @MainActor in
                self?.isServerRunning = isRunning
            }
        }
        // Publish the Bonjour TXT only after the underlying NWListener has
        // transitioned to `.ready`. Advertising earlier races the socket and
        // causes ECONNREFUSED for fast clients (the CLI's mDNS-resolve loop).
        server.onReady = { [weak self] in
            Task { @MainActor in
                self?.startMDNS()
            }
        }
        httpServer = server
        httpServer?.start()
    }

    private func registerHandlers(rendererState: RendererState) {
        let ctx = handlerContext
        ctx.scriptPlaybackState = scriptPlaybackState
        router.handlerContext = ctx
        router.scriptPlaybackState = scriptPlaybackState

        let safariAuth = SafariAuthHelper()
        safariAuth.handlerContext = ctx
        registerSafariAuthHandler(context: ctx, safariAuth: safariAuth)
        registerToastHandler()
        registerReportIssueHandler()

        NavigationHandler(context: ctx).register(on: router)
        ScreenshotHandler(context: ctx).register(on: router)
        DOMHandler(context: ctx).register(on: router)
        InteractionHandler(context: ctx).register(on: router)
        TapCalibrationHandler().register(on: router)
        ScrollHandler(context: ctx).register(on: router)
        DeviceHandler(
            context: ctx,
            deviceInfo: deviceInfo,
            rendererState: rendererState,
            viewportState: viewportState
        ).register(on: router)
        EvaluateHandler(context: ctx).register(on: router)
        ConsoleHandler(context: ctx).register(on: router)
        NetworkHandler(context: ctx).register(on: router)
        WebSocketHandler(context: ctx).register(on: router)
        MutationHandler(context: ctx).register(on: router)
        ShadowDOMHandler(context: ctx).register(on: router)
        BrowserManagementHandler(context: ctx, viewportState: viewportState).register(on: router)
        LLMHandler(context: ctx).register(on: router)
        BookmarkHandler(context: ctx).register(on: router)
        HistoryHandler(context: ctx).register(on: router)
        NetworkInspectorHandler(context: ctx).register(on: router)
        AIHandler(context: ctx).register(on: router)
        Snapshot3DHandler(context: ctx).register(on: router)
        CommentaryHandler(context: ctx).register(on: router)
        HighlightHandler(context: ctx).register(on: router)
        SwipeHandler(context: ctx).register(on: router)
        ScriptHandler(
            context: ctx,
            router: router,
            playbackState: scriptPlaybackState,
            setRecordingMode: { [weak self] isRecording in
                await self?.setScriptRecording(isRecording)
            }
        ).register(on: router)

        // Renderer switching handler
        RendererHandler(
            context: ctx,
            rendererState: rendererState,
            onSwitch: { [weak self] engine in
                await self?.switchRenderer(to: engine)
            }
        ).register(on: router)
    }

    @MainActor
    private func registerSafariAuthHandler(context: HandlerContext, safariAuth: SafariAuthHelper) {
        router.register("safari-auth") { body in
            await MainActor.run {
                guard let renderer = context.renderer else {
                    return errorResponse(code: "NO_WEBVIEW", message: "No WebView")
                }
                let urlString = body["url"] as? String
                guard let url = urlString.flatMap({ URL(string: $0) }) ?? renderer.currentURL else {
                    return errorResponse(code: "NO_URL", message: "No URL to authenticate")
                }
                safariAuth.authenticate(url: url)
                return successResponse(["started": true, "url": url.absoluteString])
            }
        }
    }

    @MainActor
    private func registerToastHandler() {
        router.register("toast") { body in
            guard let message = body["message"] as? String else {
                return errorResponse(code: "MISSING_PARAM", message: "message is required")
            }
            await self.showShellToast(message)
            return successResponse(["message": message])
        }
    }

    @MainActor
    private func registerReportIssueHandler() {
        router.register("report-issue") { [deviceInfo] body in
            guard body["category"] is String else {
                return errorResponse(code: "MISSING_PARAM", message: "category is required")
            }
            guard body["command"] is String else {
                return errorResponse(code: "MISSING_PARAM", message: "command is required")
            }
            do {
                let record = try FeedbackStore.save(
                    payload: body,
                    platform: "macos",
                    deviceID: deviceInfo.id,
                    deviceName: deviceInfo.name
                )
                return successResponse([
                    "reportId": record.reportID,
                    "storedAt": record.storedAt,
                    "platform": "macos",
                    "deviceId": deviceInfo.id
                ])
            } catch {
                return errorResponse(code: "WEBVIEW_ERROR", message: error.localizedDescription)
            }
        }
    }

    /// Switches active renderer with cookie migration.
    func switchRenderer(to engine: RendererState.Engine) async {
        guard let rendererState else { return }
        guard engine != rendererState.activeEngine else { return }

        rendererState.isSwitching = true

        // swiftlint:disable:next force_unwrapping
        let source = handlerContext.renderer!
        let target = renderer(for: engine)

        // Stop any background activity on the outgoing renderer before async work
        // so its tasks don't interleave with CEF's main-thread RunLoop source.
        source.willDeactivate()

        // Persist the source state into the shared jar, then migrate directly
        // where safe so renderer switching preserves auth state.
        await handlerContext.persistRendererCookiesToSharedJar()
        await CookieMigrator.migrate(from: source, to: target)
        handlerContext.renderer = target
        await handlerContext.syncSharedCookiesIntoRenderer(force: true)

        // Load the same URL in the target renderer
        if let url = source.currentURL, url.absoluteString != "about:blank" {
            target.load(url: url)
        }

        rendererState.activeEngine = engine
        await waitForRendererAttachment(target)
        target.didActivate()
        if engine == .webkit {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        rendererState.isSwitching = false

        if engine == .chromium {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                _ = self?.viewportState.reapplyCurrentConfiguration()
            }
        }

        // Update the advertised TXT record with the active engine.
        startMDNS()
    }

    func setScriptRecording(_ isRecording: Bool) {
        guard self.isScriptRecording != isRecording else { return }
        self.isScriptRecording = isRecording

        if isRecording {
            let window = NSApplication.shared.keyWindow
            scriptRecordingWindow = window
            scriptRecordingWasFullscreen = window?.styleMask.contains(.fullScreen) ?? false
            if let window, !scriptRecordingWasFullscreen {
                window.toggleFullScreen(nil)
            }
            return
        }

        let window = scriptRecordingWindow ?? NSApplication.shared.keyWindow
        if let window, !scriptRecordingWasFullscreen, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        scriptRecordingWindow = nil
        scriptRecordingWasFullscreen = false
    }

    func requestScriptAbort() {
        _ = scriptPlaybackState.requestAbort()
    }

    private func renderer(for engine: RendererState.Engine) -> any RendererEngine {
        switch engine {
        case .webkit:
            if let wkRenderer {
                return wkRenderer
            }
            let renderer = WKWebViewRenderer()
            renderer.onScriptMessage = { [weak self] name, body in
                self?.handlerContext.handleScriptMessage(name: name, body: body)
            }
            wkRenderer = renderer
            return renderer
        case .chromium:
            if let cefRenderer {
                return cefRenderer
            }
            let renderer = CEFRenderer()
            renderer.onScriptMessage = { [weak self] name, body in
                self?.handlerContext.handleScriptMessage(name: name, body: body)
            }
            cefRenderer = renderer
            return renderer
        }
    }

    private func waitForRendererAttachment(_ renderer: any RendererEngine) async {
        let view = renderer.makeView()
        for _ in 0..<20 {
            if view.window != nil {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func startMDNS() {
        let engine = rendererState?.activeEngine.rawValue ?? "webkit"
        httpServer?.configureBonjourService(
            name: deviceInfo.name,
            type: "_kelpie._tcp",
            txtRecord: NWTXTRecord(deviceInfo.txtRecord(engine: engine))
        )
    }

    func stop() {
        httpServer?.stop()
        isServerRunning = false
        isMDNSAdvertising = false
    }

    func showShellToast(_ message: String) {
        toastDismissTask?.cancel()
        shellToastMessage = message

        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.shellToastMessage = nil
        }
    }

    private static func getLocalIPAddress() -> String {
        var address = "0.0.0.0"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }

    private static func firstAvailablePort(startingAt preferredPort: UInt16, attempts: UInt16 = 32) -> UInt16 {
        for offset in UInt16(0)..<attempts {
            let candidate = preferredPort &+ offset
            if reservedPorts.contains(candidate) {
                continue
            }
            if canBind(port: candidate) {
                return candidate
            }
        }
        return preferredPort
    }

    private static func canBind(port: UInt16) -> Bool {
        let fd = socket(AF_INET6, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = port.bigEndian
        address.sin6_addr = in6addr_any

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
            }
        }
    }

    private static var reservedPorts: Set<UInt16> {
        var ports: Set<UInt16> = []
        #if DEBUG
        ports.insert(8421) // Reserved for AppReveal on debug builds.
        #endif
        return ports
    }

    private func awaitSharedCookieImportThenLoad(url: URL) {
        Task { @MainActor [weak self] in
            await self?.handlerContext.syncSharedCookiesIntoRenderer(force: true)
            self?.handlerContext.load(url: url)
        }
    }
}
