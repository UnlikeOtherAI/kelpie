import UIKit
import WebKit

/// Handles getViewport, getDeviceInfo, getCapabilities.
struct DeviceHandler {
    let context: HandlerContext
    let deviceInfo: DeviceInfo

    func register(on router: Router) {
        router.register("get-viewport") { _ in await getViewport() }
        router.register("get-viewport-presets") { _ in await getViewportPresets() }
        router.register("get-device-info") { _ in await getDeviceInfoResponse() }
        router.register("get-capabilities") { _ in getCapabilities() }
        router.register("set-orientation") { body in await setOrientation(body) }
        router.register("get-orientation") { _ in await getOrientation() }
        router.register("debug-screens") { _ in await debugScreens() }
        router.register("debug-attach-local-tv") { _ in await debugAttachLocalTV() }
        router.register("debug-detach-tv") { _ in await debugDetachTV() }
        router.register("set-tv-sync") { body in await setTVSync(body) }
        router.register("get-tv-sync") { _ in await getTVSync() }
        router.register("set-debug-overlay") { body in setDebugOverlay(body) }
        router.register("get-debug-overlay") { _ in getDebugOverlay() }
    }

    @MainActor
    private func getViewport() async -> [String: Any] {
        guard let webView = context.webView else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        let bounds = webView.bounds
        let scale = UIScreen.main.scale
        let orientation = UIDevice.current.orientation.isLandscape ? "landscape" : "portrait"
        return [
            "width": Int(bounds.width),
            "height": Int(bounds.height),
            "devicePixelRatio": scale,
            "platform": "ios",
            "deviceName": deviceInfo.name,
            "orientation": orientation,
        ]
    }

    @MainActor
    private func getViewportPresets() async -> [String: Any] {
        let availablePresetIDs = currentTabletViewportAvailablePresetIDs()
        let storedPresetID = UserDefaults.standard.string(forKey: ipadMobileStagePresetDefaultsKey) ?? ""
        let activePresetID: Any = availablePresetIDs.contains(storedPresetID) ? storedPresetID : NSNull()

        return successResponse([
            "supportsViewportPresets": true,
            "presets": tabletViewportPresets.map(viewportPresetPayload),
            "availablePresetIds": availablePresetIDs,
            "activePresetId": activePresetID,
        ])
    }

    private func getDeviceInfoResponse() async -> [String: Any] {
        let device = UIDevice.current
        let screen = await UIScreen.main
        return [
            "device": [
                "id": deviceInfo.id,
                "name": deviceInfo.name,
                "model": deviceInfo.model,
                "platform": "ios",
            ],
            "display": [
                "width": deviceInfo.width,
                "height": deviceInfo.height,
                "scale": await screen.scale,
            ],
            "network": ["ip": "0.0.0.0", "port": deviceInfo.port],
            "browser": ["engine": "WebKit", "version": device.systemVersion],
            "app": ["version": deviceInfo.version, "build": "1"],
            "system": ["os": "iOS", "osVersion": device.systemVersion],
        ]
    }

    @MainActor
    private func getOrientation() async -> [String: Any] {
        let isLandscape = UIDevice.current.orientation.isLandscape
        let lock = OrientationManager.shared.lock
        let locked: String? = switch lock {
        case .landscape, .landscapeLeft, .landscapeRight: "landscape"
        case .portrait, .portraitUpsideDown: "portrait"
        default: nil
        }
        return successResponse([
            "orientation": isLandscape ? "landscape" : "portrait",
            "locked": locked as Any,
        ])
    }

    @MainActor
    private func setOrientation(_ body: [String: Any]) async -> [String: Any] {
        guard let orientation = body["orientation"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "orientation is required (portrait|landscape|auto)")
        }
        let manager = OrientationManager.shared
        switch orientation.lowercased() {
        case "landscape":
            manager.lock = .landscape
            // Request geometry update on the window scene
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
                scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        case "portrait":
            manager.lock = .portrait
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        case "auto":
            manager.lock = .all
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        default:
            return errorResponse(code: "INVALID_PARAM", message: "orientation must be portrait, landscape, or auto")
        }
        return successResponse(["orientation": orientation])
    }

    @MainActor
    private func debugScreens() async -> [String: Any] {
        let screens = UIScreen.screens
        let scenes = UIApplication.shared.connectedScenes.map { scene -> [String: Any] in
            [
                "role": scene.session.role.rawValue,
                "state": "\(scene.activationState.rawValue)",
                "configuration": scene.session.configuration.name ?? "nil",
            ]
        }
        let mgr = ExternalDisplayManager.shared

        // Native layers — include origin coordinates for all frames
        var windowInfo: [String: Any] = ["exists": false]
        var webViewInfo: [String: Any] = ["exists": false]
        var vcViewInfo: [String: Any] = ["exists": false]
        if let win = mgr.externalWindow {
            windowInfo = [
                "exists": true,
                "hidden": win.isHidden,
                "hasScene": win.windowScene != nil,
                "frame": ["x": win.frame.origin.x, "y": win.frame.origin.y, "w": win.frame.width, "h": win.frame.height],
                "bounds": ["x": win.bounds.origin.x, "y": win.bounds.origin.y, "w": win.bounds.width, "h": win.bounds.height],
            ]
            if let vcView = win.rootViewController?.view {
                vcViewInfo = [
                    "exists": true,
                    "frame": ["x": vcView.frame.origin.x, "y": vcView.frame.origin.y, "w": vcView.frame.width, "h": vcView.frame.height],
                    "bounds": ["x": vcView.bounds.origin.x, "y": vcView.bounds.origin.y, "w": vcView.bounds.width, "h": vcView.bounds.height],
                ]
            }
        }
        if let wv = context.webView {
            let sv = wv.scrollView
            webViewInfo = [
                "exists": true,
                "frame": ["x": wv.frame.origin.x, "y": wv.frame.origin.y, "w": wv.frame.width, "h": wv.frame.height],
                "bounds": ["x": wv.bounds.origin.x, "y": wv.bounds.origin.y, "w": wv.bounds.width, "h": wv.bounds.height],
                "contentScaleFactor": wv.contentScaleFactor,
                "pageZoom": wv.pageZoom,
                "scrollView": [
                    "contentSize": ["w": sv.contentSize.width, "h": sv.contentSize.height],
                    "contentOffset": ["x": sv.contentOffset.x, "y": sv.contentOffset.y],
                    "zoomScale": sv.zoomScale,
                    "contentInset": ["t": sv.contentInset.top, "l": sv.contentInset.left, "b": sv.contentInset.bottom, "r": sv.contentInset.right],
                ],
            ]
        }

        // HTML layer — get CSS viewport and document size via JS
        var htmlInfo: [String: Any] = [:]
        if let wv = context.webView {
            let js = """
            JSON.stringify({
                innerWidth: window.innerWidth,
                innerHeight: window.innerHeight,
                outerWidth: window.outerWidth,
                outerHeight: window.outerHeight,
                screenX: window.screenX,
                screenY: window.screenY,
                scrollX: window.scrollX,
                scrollY: window.scrollY,
                devicePixelRatio: window.devicePixelRatio,
                documentWidth: document.documentElement.scrollWidth,
                documentHeight: document.documentElement.scrollHeight,
                clientWidth: document.documentElement.clientWidth,
                clientHeight: document.documentElement.clientHeight,
                bodyWidth: document.body ? document.body.scrollWidth : null,
                bodyHeight: document.body ? document.body.scrollHeight : null,
                bodyOffsetLeft: document.body ? document.body.offsetLeft : null,
                bodyOffsetTop: document.body ? document.body.offsetTop : null,
                viewportMeta: (function(){ var m = document.querySelector('meta[name=viewport]'); return m ? m.content : null; })(),
                visualViewport: window.visualViewport ? {
                    width: window.visualViewport.width,
                    height: window.visualViewport.height,
                    offsetLeft: window.visualViewport.offsetLeft,
                    offsetTop: window.visualViewport.offsetTop,
                    pageLeft: window.visualViewport.pageLeft,
                    pageTop: window.visualViewport.pageTop,
                    scale: window.visualViewport.scale
                } : null
            })
            """
            if let result = try? await wv.evaluateJavaScript(js) as? String,
               let data = result.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                htmlInfo = parsed
            }
        }

        return successResponse([
            "screenCount": screens.count,
            "screens": screens.enumerated().map { i, s in
                [
                    "index": i,
                    "width": s.bounds.width,
                    "height": s.bounds.height,
                    "scale": s.scale,
                    "nativeScale": s.nativeScale,
                    "mirrored": s.mirrored != nil,
                ]
            },
            "scenes": scenes,
            "externalDisplay": [
                "connected": mgr.isConnected,
                "attachPath": mgr.attachPath ?? "none",
                "port": mgr.externalPort,
                "syncEnabled": mgr.isSyncEnabled,
            ],
            "window": windowInfo,
            "vcView": vcViewInfo,
            "webView": webViewInfo,
            "html": htmlInfo,
        ])
    }

    @MainActor
    private func debugAttachLocalTV() async -> [String: Any] {
        ExternalDisplayManager.shared.attachDebugLocalTV()
        return successResponse([
            "connected": ExternalDisplayManager.shared.isConnected,
            "attachPath": ExternalDisplayManager.shared.attachPath ?? "none",
            "port": ExternalDisplayManager.shared.externalPort,
        ])
    }

    @MainActor
    private func debugDetachTV() async -> [String: Any] {
        ExternalDisplayManager.shared.detach()
        return successResponse(["connected": false])
    }

    @MainActor
    private func setTVSync(_ body: [String: Any]) -> [String: Any] {
        let enabled = body["enabled"] as? Bool ?? true
        ExternalDisplayManager.shared.setSyncEnabled(enabled)
        return successResponse([
            "enabled": enabled,
            "connected": ExternalDisplayManager.shared.isConnected,
        ])
    }

    @MainActor
    private func getTVSync() -> [String: Any] {
        successResponse([
            "enabled": ExternalDisplayManager.shared.isSyncEnabled,
            "connected": ExternalDisplayManager.shared.isConnected,
            "attachPath": ExternalDisplayManager.shared.attachPath as Any,
        ])
    }

    private func setDebugOverlay(_ body: [String: Any]) -> [String: Any] {
        let enabled = body["enabled"] as? Bool ?? true
        UserDefaults.standard.set(enabled, forKey: "debugOverlay")
        return successResponse(["enabled": enabled])
    }

    private func getDebugOverlay() -> [String: Any] {
        successResponse(["enabled": UserDefaults.standard.bool(forKey: "debugOverlay")])
    }

    private func getCapabilities() -> [String: Any] {
        [
            "cdp": false,
            "nativeAPIs": true,
            "bridgeScripts": true,
            "screenshot": true,
            "fullPageScreenshot": true,
            "cookies": true,
            "storage": true,
            "geolocation": false,
            "requestInterception": false,
            "consoleLogs": true,
            "networkLogs": false,
            "mutations": true,
            "shadowDOM": true,
            "clipboard": true,
            "keyboard": true,
            "tabs": true,
            "iframes": true,
            "dialogs": true,
            "viewportPresets": true,
        ]
    }

    private func viewportPresetPayload(_ preset: TabletViewportPreset) -> [String: Any] {
        [
            "id": preset.id,
            "name": preset.name,
            "inches": preset.displaySizeLabel,
            "pixels": preset.pixelResolutionLabel,
            "viewport": [
                "portrait": [
                    "width": Int(preset.portraitSize.width),
                    "height": Int(preset.portraitSize.height),
                ],
                "landscape": [
                    "width": Int(preset.portraitSize.height),
                    "height": Int(preset.portraitSize.width),
                ],
            ],
        ]
    }
}
