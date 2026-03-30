import Foundation
import AppKit

/// Observable state for the HTTP server, mDNS, and renderer management.
@MainActor
final class ServerState: ObservableObject {
    @Published var isServerRunning = false
    @Published var isMDNSAdvertising = false
    @Published var ipAddress: String = "0.0.0.0"

    let deviceInfo: DeviceInfo
    let router = Router()
    let handlerContext = HandlerContext()

    var rendererState: RendererState?

    // Both renderers are created eagerly for instant switching
    private(set) var wkRenderer: WKWebViewRenderer?
    private(set) var cefRenderer: CEFRenderer?

    private var httpServer: HTTPServer?
    private var mdnsAdvertiser: MDNSAdvertiser?

    init(port: UInt16 = 8420) {
        self.deviceInfo = DeviceInfo.current(port: Int(port))
        self.ipAddress = Self.getLocalIPAddress()
    }

    func startHTTPServer() {
        // Initialize both renderers
        let wk = WKWebViewRenderer()
        let cef = CEFRenderer()
        wkRenderer = wk
        cefRenderer = cef

        // Wire script message handling
        wk.onScriptMessage = { [weak self] name, body in
            self?.handlerContext.handleScriptMessage(name: name, body: body)
        }
        cef.onScriptMessage = { [weak self] name, body in
            self?.handlerContext.handleScriptMessage(name: name, body: body)
        }

        // Start with persisted renderer (or WebKit by default)
        let startEngine = rendererState?.activeEngine ?? .webkit
        let activeRenderer: any RendererEngine = startEngine == .chromium ? cef : wk
        handlerContext.renderer = activeRenderer
        let homeURL = URL(string: UserDefaults.standard.string(forKey: "homeURL") ?? defaultHomeURL)!
        activeRenderer.load(url: homeURL)

        registerHandlers()
        router.registerStubs()
        httpServer = HTTPServer(port: UInt16(deviceInfo.port), router: router)
        httpServer?.start()
        isServerRunning = true
    }

    private func registerHandlers() {
        let ctx = handlerContext
        router.handlerContext = ctx

        // Safari auth
        let safariAuth = SafariAuthHelper()
        safariAuth.handlerContext = ctx
        router.register("safari-auth") { body in
            let result: [String: Any] = await MainActor.run {
                guard let renderer = ctx.renderer else {
                    return errorResponse(code: "NO_WEBVIEW", message: "No WebView")
                }
                let urlStr = body["url"] as? String
                guard let url = urlStr.flatMap({ URL(string: $0) }) ?? renderer.currentURL else {
                    return errorResponse(code: "NO_URL", message: "No URL to authenticate")
                }
                safariAuth.authenticate(url: url)
                return successResponse(["started": true, "url": url.absoluteString])
            }
            return result
        }

        // Toast
        router.register("toast") { body in
            guard let message = body["message"] as? String else {
                return errorResponse(code: "MISSING_PARAM", message: "message is required")
            }
            await ctx.showToast(message)
            return successResponse(["message": message])
        }

        NavigationHandler(context: ctx).register(on: router)
        ScreenshotHandler(context: ctx).register(on: router)
        DOMHandler(context: ctx).register(on: router)
        InteractionHandler(context: ctx).register(on: router)
        ScrollHandler(context: ctx).register(on: router)
        DeviceHandler(context: ctx, deviceInfo: deviceInfo, rendererState: rendererState!).register(on: router)
        EvaluateHandler(context: ctx).register(on: router)
        ConsoleHandler(context: ctx).register(on: router)
        NetworkHandler(context: ctx).register(on: router)
        MutationHandler(context: ctx).register(on: router)
        ShadowDOMHandler(context: ctx).register(on: router)
        BrowserManagementHandler(context: ctx).register(on: router)
        LLMHandler(context: ctx).register(on: router)
        BookmarkHandler(context: ctx).register(on: router)
        HistoryHandler(context: ctx).register(on: router)
        NetworkInspectorHandler(context: ctx).register(on: router)

        // Renderer switching handler
        RendererHandler(
            context: ctx,
            rendererState: rendererState!,
            onSwitch: { [weak self] engine in
                await self?.switchRenderer(to: engine)
            }
        ).register(on: router)
    }

    /// Switches active renderer with cookie migration.
    func switchRenderer(to engine: RendererState.Engine) async {
        guard let rendererState, let wkRenderer, let cefRenderer else { return }
        guard engine != rendererState.activeEngine else { return }

        rendererState.isSwitching = true

        let source = handlerContext.renderer!
        let target: any RendererEngine = engine == .webkit ? wkRenderer : cefRenderer

        // Migrate cookies
        await CookieMigrator.migrate(from: source, to: target)

        // Load the same URL in the target renderer
        if let url = source.currentURL, url.absoluteString != "about:blank" {
            target.load(url: url)
        }

        // Swap
        handlerContext.renderer = target
        rendererState.activeEngine = engine
        rendererState.isSwitching = false

        // Update mDNS TXT record with new engine
        mdnsAdvertiser?.restart(txtRecord: deviceInfo.txtRecord(engine: engine.rawValue))
    }

    func startMDNS() {
        let engine = rendererState?.activeEngine.rawValue ?? "webkit"
        mdnsAdvertiser = MDNSAdvertiser(txtRecord: deviceInfo.txtRecord(engine: engine))
        mdnsAdvertiser?.start()
        isMDNSAdvertising = true
    }

    func stop() {
        httpServer?.stop()
        mdnsAdvertiser?.stop()
        isServerRunning = false
        isMDNSAdvertising = false
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
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }
}
