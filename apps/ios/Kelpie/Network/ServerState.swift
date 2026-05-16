import Foundation
import UIKit
import WebKit

/// Observable state for the HTTP server and mDNS advertiser.
final class ServerState: ObservableObject {
    @Published var isServerRunning = false
    @Published var isMDNSAdvertising = false
    @Published var ipAddress: String = "0.0.0.0"
    @Published var isScriptRecording = false
    /// Set by the `show-panel` debug endpoint to open a UI panel programmatically.
    @Published var activePanel: String?

    let deviceInfo: DeviceInfo
    let router = Router()
    let handlerContext = HandlerContext()
    let scriptPlaybackState = ScriptPlaybackState()
    weak var webView: WKWebView?
    var tabStore: TabStore?

    private var httpServer: HTTPServer?
    private var mdnsAdvertiser: MDNSAdvertiser?
    private var preScriptOrientationLock: UIInterfaceOrientationMask?

    init(port: UInt16 = 8420) {
        self.deviceInfo = DeviceInfo.current(port: Int(port))
        self.ipAddress = Self.getLocalIPAddress()
    }

    init(deviceInfo: DeviceInfo) {
        self.deviceInfo = deviceInfo
        self.ipAddress = Self.getLocalIPAddress()
    }

    @MainActor
    func startHTTPServer() {
        registerHandlers()
        router.registerFallbacks()
        do {
            httpServer = try HTTPServer(port: UInt16(deviceInfo.port), router: router)
        } catch {
            print("[ServerState] Failed to construct HTTPServer: \(error)")
            return
        }
        httpServer?.start()
        DispatchQueue.main.async { self.isServerRunning = true }
    }

    @MainActor
    private func registerHandlers() {
        let ctx = handlerContext
        ctx.scriptPlaybackState = scriptPlaybackState
        ctx.tabStore = tabStore
        router.handlerContext = ctx
        router.scriptPlaybackState = scriptPlaybackState

        let setActivePanel: @MainActor (String) -> Void = { [weak self] panel in
            self?.activePanel = panel
        }
        registerSafariAuthHandler(context: ctx)
        registerToastHandler(context: ctx)
        registerReportIssueHandler()
        registerShowPanelHandler(setActivePanel: setActivePanel)

        NavigationHandler(context: ctx).register(on: router)
        ScreenshotHandler(context: ctx).register(on: router)
        DOMHandler(context: ctx).register(on: router)
        InteractionHandler(context: ctx).register(on: router)
        TapCalibrationHandler().register(on: router)
        ScrollHandler(context: ctx).register(on: router)
        DeviceHandler(context: ctx, deviceInfo: deviceInfo).register(on: router)
        EvaluateHandler(context: ctx).register(on: router)
        ConsoleHandler(context: ctx).register(on: router)
        NetworkHandler(context: ctx).register(on: router)
        WebSocketHandler(context: ctx).register(on: router)
        MutationHandler(context: ctx).register(on: router)
        ShadowDOMHandler(context: ctx).register(on: router)
        BrowserManagementHandler(context: ctx).register(on: router)
        LLMHandler(context: ctx).register(on: router)
        AIHandler(context: ctx).register(on: router)
        Snapshot3DHandler(context: ctx).register(on: router)
        BookmarkHandler(context: ctx).register(on: router)
        HistoryHandler(context: ctx).register(on: router)
        NetworkInspectorHandler(context: ctx).register(on: router)
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
    }

    @MainActor
    private func registerSafariAuthHandler(context: HandlerContext) {
        router.register("safari-auth") { body in
            let resolved: (WKWebView, URL)? = await MainActor.run {
                guard let webView = context.webView else { return nil }
                let urlString = body["url"] as? String
                guard let url = urlString.flatMap({ URL(string: $0) }) ?? webView.url else {
                    return nil
                }
                return (webView, url)
            }

            guard let (webView, url) = resolved else {
                if await MainActor.run(body: { context.webView }) == nil {
                    return errorResponse(code: "NO_WEBVIEW", message: "No WebView")
                }
                return errorResponse(code: "NO_URL", message: "No URL to authenticate")
            }

            do {
                try await context.safariAuth.authenticate(url: url, webView: webView)
                return successResponse(["completed": true, "url": url.absoluteString])
            } catch SafariAuthError.webViewUnavailable {
                return errorResponse(code: "NO_WEBVIEW", message: "WebView released before auth completion")
            } catch SafariAuthError.session(let underlying) {
                return errorResponse(
                    code: "SAFARI_AUTH_FAILED",
                    message: underlying.localizedDescription
                )
            } catch {
                return errorResponse(code: "SAFARI_AUTH_FAILED", message: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func registerToastHandler(context: HandlerContext) {
        router.register("toast") { body in
            guard let message = body["message"] as? String else {
                return errorResponse(code: "MISSING_PARAM", message: "message is required")
            }
            await context.showToast(message)
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
                    platform: "ios",
                    deviceID: deviceInfo.id,
                    deviceName: deviceInfo.name
                )
                return successResponse([
                    "reportId": record.reportID,
                    "storedAt": record.storedAt,
                    "platform": "ios",
                    "deviceId": deviceInfo.id
                ])
            } catch {
                return errorResponse(code: "WEBVIEW_ERROR", message: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func registerShowPanelHandler(setActivePanel: @escaping @MainActor (String) -> Void) {
        router.register("show-panel") { body in
            guard let panel = body["panel"] as? String else {
                return errorResponse(code: "MISSING_PARAM", message: "panel is required")
            }
            let valid = ["history", "bookmarks", "network-inspector", "settings", "ai"]
            guard valid.contains(panel) else {
                return errorResponse(code: "INVALID_PARAM", message: "panel must be one of: \(valid.joined(separator: ", "))")
            }
            await setActivePanel(panel)
            return successResponse(["panel": panel])
        }
    }

    @MainActor
    func setScriptRecording(_ isRecording: Bool) {
        guard self.isScriptRecording != isRecording else { return }
        self.isScriptRecording = isRecording

        let manager = OrientationManager.shared
        if isRecording {
            preScriptOrientationLock = manager.lock
            if manager.lock == .all {
                let orientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation
                let lock: UIInterfaceOrientationMask = orientation?.isLandscape == true ? .landscape : .portrait
                manager.lock = lock
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: lock))
                    scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
            return
        }

        if let previousLock = preScriptOrientationLock {
            manager.lock = previousLock
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                if previousLock != .all {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: previousLock))
                }
                scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
        preScriptOrientationLock = nil
    }

    func requestScriptAbort() {
        _ = scriptPlaybackState.requestAbort()
    }

    func startMDNS() {
        if let mdnsAdvertiser {
            mdnsAdvertiser.start()
            return
        }

        guard let httpServer else {
            print("[mDNS] HTTPServer not started; cannot publish service")
            return
        }

        let advertiser = MDNSAdvertiser(txtRecord: deviceInfo.txtRecord, httpServer: httpServer)
        advertiser.onAdvertisingChange = { [weak self] isAdvertising in
            DispatchQueue.main.async {
                self?.isMDNSAdvertising = isAdvertising
            }
        }
        mdnsAdvertiser = advertiser
        advertiser.start()
    }

    func ensureMDNSAdvertising() {
        guard !isMDNSAdvertising else { return }
        startMDNS()
    }

    func stopMDNS() {
        mdnsAdvertiser?.stop()
    }

    func stop() {
        httpServer?.stop()
        stopMDNS()
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
}
