import AppKit

/// Handles getViewport, getDeviceInfo, getCapabilities.
struct DeviceHandler {
    let context: HandlerContext
    let deviceInfo: DeviceInfo
    let rendererState: RendererState
    let viewportState: ViewportState

    func register(on router: Router) {
        router.register("get-viewport") { _ in await getViewport() }
        router.register("get-viewport-presets") { _ in await getViewportPresets() }
        router.register("get-device-info") { _ in await getDeviceInfoResponse() }
        router.register("get-capabilities") { _ in await getCapabilities() }
        router.register("set-orientation") { body in await setOrientation(body) }
        router.register("get-orientation") { _ in await getOrientation() }
    }

    @MainActor
    private func getViewport() async -> [String: Any] {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let scale = screen.backingScaleFactor
        let viewport = viewportState.currentViewportDimensions
        let orientation = viewport.width >= viewport.height ? "landscape" : "portrait"
        return [
            "width": viewport.width,
            "height": viewport.height,
            "devicePixelRatio": scale,
            "platform": "macos",
            "deviceName": deviceInfo.name,
            "orientation": orientation,
        ]
    }

    @MainActor
    private func getViewportPresets() async -> [String: Any] {
        successResponse([
            "supportsViewportPresets": true,
            "presets": allMacViewportPresets.map { preset in
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
            },
            "availablePresetIds": viewportState.availablePresets.map(\.id),
            "activePresetId": viewportState.activePresetId as Any,
        ])
    }

    @MainActor
    private func getDeviceInfoResponse() async -> [String: Any] {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        return [
            "device": [
                "id": deviceInfo.id,
                "name": deviceInfo.name,
                "model": deviceInfo.model,
                "platform": "macos",
            ],
            "display": [
                "width": deviceInfo.width,
                "height": deviceInfo.height,
                "scale": screen.backingScaleFactor,
            ],
            "network": ["ip": "0.0.0.0", "port": deviceInfo.port],
            "browser": [
                "engine": rendererState.activeEngine.rawValue,
                "version": ProcessInfo.processInfo.operatingSystemVersionString,
            ],
            "app": ["version": deviceInfo.version, "build": "1"],
            "system": [
                "os": "macOS",
                "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            ],
        ]
    }

    @MainActor
    private func getCapabilities() async -> [String: Any] {
        [
            "cdp": rendererState.activeEngine == .chromium,
            "nativeAPIs": true,
            "bridgeScripts": true,
            "screenshot": true,
            "fullPageScreenshot": true,
            "cookies": true,
            "storage": true,
            "geolocation": false,
            "requestInterception": rendererState.activeEngine == .chromium,
            "consoleLogs": true,
            "networkLogs": true,
            "mutations": true,
            "shadowDOM": true,
            "clipboard": true,
            "keyboard": false,
            "tabs": true,
            "iframes": true,
            "dialogs": true,
            "rendererSwitching": true,
            "viewportPresets": true,
        ]
    }

    @MainActor
    private func getOrientation() async -> [String: Any] {
        successResponse([
            "orientation": viewportState.reportedOrientation.rawValue,
            "locked": viewportState.supportsOrientationSelection ? viewportState.reportedOrientation.rawValue : NSNull(),
        ])
    }

    @MainActor
    private func setOrientation(_ body: [String: Any]) async -> [String: Any] {
        guard let orientation = body["orientation"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "orientation is required (portrait|landscape|auto)")
        }

        switch orientation.lowercased() {
        case "portrait", "landscape":
            break
        case "auto":
            return [
                "success": false,
                "error": [
                    "code": "INVALID_STATE",
                    "message": "Auto orientation is not supported for staged macOS viewports. Use a named preset and set portrait or landscape explicitly.",
                    "reason": "auto-unsupported",
                ],
            ]
        default:
            return errorResponse(code: "INVALID_PARAM", message: "orientation must be portrait, landscape, or auto")
        }

        guard case .preset = viewportState.mode else {
            let error: [String: Any]
            switch viewportState.mode {
            case .full:
                error = [
                    "code": "INVALID_STATE",
                    "message": "Orientation can only be changed on macOS when a named viewport preset is active. Select a smaller viewport preset first.",
                    "reason": "full-viewport",
                ]
            case .custom:
                error = [
                    "code": "INVALID_STATE",
                    "message": "Orientation cannot be changed for raw custom macOS viewports. Resize explicitly or switch to a named viewport preset first.",
                    "reason": "custom-viewport",
                ]
            case .preset:
                error = [
                    "code": "INVALID_STATE",
                    "message": "Orientation could not be changed for the current macOS viewport mode.",
                    "reason": "unavailable",
                ]
            }
            return ["success": false, "error": error]
        }

        guard let nextOrientation = ViewportOrientation(rawValue: orientation.lowercased()) else {
            return errorResponse(code: "INVALID_PARAM", message: "orientation must be portrait or landscape")
        }

        viewportState.selectOrientation(nextOrientation)
        await context.waitForViewportSize(CGSize(
            width: CGFloat(viewportState.currentViewportDimensions.width),
            height: CGFloat(viewportState.currentViewportDimensions.height)
        ))
        let viewport = viewportState.currentViewportDimensions
        return successResponse([
            "orientation": viewportState.reportedOrientation.rawValue,
            "locked": viewportState.reportedOrientation.rawValue,
            "activePresetId": viewportState.activePresetId as Any,
            "viewport": [
                "width": viewport.width,
                "height": viewport.height,
            ],
        ])
    }
}
