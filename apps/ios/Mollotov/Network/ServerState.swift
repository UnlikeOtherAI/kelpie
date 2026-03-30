import Foundation
import WebKit

/// Observable state for the HTTP server and mDNS advertiser.
final class ServerState: ObservableObject {
    @Published var isServerRunning = false
    @Published var isMDNSAdvertising = false
    @Published var ipAddress: String = "0.0.0.0"

    let deviceInfo: DeviceInfo
    let router = Router()
    let handlerContext = HandlerContext()
    weak var webView: WKWebView?

    private var httpServer: HTTPServer?
    private var mdnsAdvertiser: MDNSAdvertiser?

    init(port: UInt16 = 8420) {
        self.deviceInfo = DeviceInfo.current(port: Int(port))
        self.ipAddress = Self.getLocalIPAddress()
    }

    @MainActor
    func startHTTPServer() {
        registerHandlers()
        router.registerStubs() // Fill remaining unimplemented methods
        httpServer = HTTPServer(port: UInt16(deviceInfo.port), router: router)
        httpServer?.start()
        DispatchQueue.main.async { self.isServerRunning = true }
    }

    @MainActor
    private func registerHandlers() {
        let ctx = handlerContext
        router.handlerContext = ctx

        // Safari auth — open current URL in Safari-backed auth session
        router.register("safari-auth") { body in
            let result: [String: Any] = await MainActor.run {
                guard let webView = ctx.webView else {
                    return errorResponse(code: "NO_WEBVIEW", message: "No WebView")
                }
                let urlStr = body["url"] as? String
                guard let url = urlStr.flatMap({ URL(string: $0) }) ?? webView.url else {
                    return errorResponse(code: "NO_URL", message: "No URL to authenticate")
                }
                ctx.safariAuth.authenticate(url: url, webView: webView, from: webView.window) {}
                return successResponse(["started": true, "url": url.absoluteString])
            }
            return result
        }

        // Toast endpoint — show a message overlay on the device
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
        DeviceHandler(context: ctx, deviceInfo: deviceInfo).register(on: router)
        EvaluateHandler(context: ctx).register(on: router)
        ConsoleHandler(context: ctx).register(on: router)
        NetworkHandler(context: ctx).register(on: router)
        MutationHandler(context: ctx).register(on: router)
        ShadowDOMHandler(context: ctx).register(on: router)
        BrowserManagementHandler(context: ctx).register(on: router)
        LLMHandler(context: ctx).register(on: router)
    }

    func startMDNS() {
        mdnsAdvertiser = MDNSAdvertiser(txtRecord: deviceInfo.txtRecord)
        mdnsAdvertiser?.start()
        DispatchQueue.main.async { self.isMDNSAdvertising = true }
    }

    func stop() {
        httpServer?.stop()
        mdnsAdvertiser?.stop()
        DispatchQueue.main.async {
            self.isServerRunning = false
            self.isMDNSAdvertising = false
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
