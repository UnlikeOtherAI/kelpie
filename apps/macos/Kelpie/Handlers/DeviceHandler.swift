import AppKit

/// Handles getViewport, getDeviceInfo, getCapabilities.
struct DeviceHandler {
    let context: HandlerContext
    let deviceInfo: DeviceInfo
    let rendererState: RendererState
    let viewportState: ViewportState

    /// Canonical list of HTTP/MCP methods that macOS does not implement.
    /// Single source of truth — `get-capabilities` reports these as
    /// `unsupported`, and `BrowserManagementHandler.register` installs
    /// `PLATFORM_NOT_SUPPORTED` stubs from this same list so the two never
    /// drift out of sync.
    static let unsupportedMethods: [String] = [
        "debug-screens",
        "set-debug-overlay",
        "get-debug-overlay",
        "set-geolocation",
        "clear-geolocation",
        "set-request-interception",
        "get-intercepted-requests",
        "clear-request-interception",
        "show-keyboard",
        "hide-keyboard",
        "get-keyboard-state",
        "is-element-obscured"
    ]

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
        // swiftlint:disable:next force_unwrapping
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
            "orientation": orientation
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
                            "height": Int(preset.portraitSize.height)
                        ],
                        "landscape": [
                            "width": Int(preset.portraitSize.height),
                            "height": Int(preset.portraitSize.width)
                        ]
                    ]
                ]
            },
            "availablePresetIds": viewportState.availablePresets.map(\.id),
            "activePresetId": viewportState.activePresetId as Any
        ])
    }

    @MainActor
    private func getDeviceInfoResponse() async -> [String: Any] {
        // swiftlint:disable:next force_unwrapping
        let screen = NSScreen.main ?? NSScreen.screens.first!
        return [
            "device": [
                "id": deviceInfo.id,
                "name": deviceInfo.name,
                "model": deviceInfo.model,
                "platform": "macos"
            ],
            "display": [
                "width": deviceInfo.width,
                "height": deviceInfo.height,
                "scale": screen.backingScaleFactor
            ],
            "network": ["ip": "0.0.0.0", "port": deviceInfo.port],
            "browser": [
                "engine": rendererState.activeEngine.rawValue,
                "version": ProcessInfo.processInfo.operatingSystemVersionString
            ],
            "app": ["version": deviceInfo.version, "build": "1"],
            "system": [
                "os": "macOS",
                "osVersion": ProcessInfo.processInfo.operatingSystemVersionString
            ]
        ]
    }

    @MainActor
    private func getCapabilities() async -> [String: Any] {
        let unsupported = Set(Self.unsupportedMethods)
        let partial = Set<String>()
        let supported = macosCapabilityMethods.filter { !unsupported.contains($0) && !partial.contains($0) }
        return successResponse([
            "version": deviceInfo.version,
            "platform": "macos",
            "supported": supported,
            "partial": Array(partial).sorted(),
            "unsupported": Array(unsupported).sorted()
        ])
    }

    @MainActor
    private func getOrientation() async -> [String: Any] {
        successResponse([
            "orientation": viewportState.reportedOrientation.rawValue,
            "locked": viewportState.supportsOrientationSelection ? viewportState.reportedOrientation.rawValue : NSNull()
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
                    "reason": "auto-unsupported"
                ]
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
                    "reason": "full-viewport"
                ]
            case .custom:
                error = [
                    "code": "INVALID_STATE",
                    "message": "Orientation cannot be changed for raw custom macOS viewports. Resize explicitly or switch to a named viewport preset first.",
                    "reason": "custom-viewport"
                ]
            case .preset:
                error = [
                    "code": "INVALID_STATE",
                    "message": "Orientation could not be changed for the current macOS viewport mode.",
                    "reason": "unavailable"
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
                "height": viewport.height
            ]
        ])
    }
}

private let macosCapabilityMethods = [
    "navigate", "back", "forward", "reload", "get-current-url", "set-home", "get-home",
    "debug-screens", "set-debug-overlay", "get-debug-overlay",
    "screenshot", "get-dom", "query-selector", "query-selector-all", "get-element-text", "get-attributes",
    "click", "tap", "fill", "type", "select-option", "check", "uncheck", "swipe",
    "scroll", "scroll2", "scroll-to-top", "scroll-to-bottom", "scroll-to-y",
    "get-viewport", "get-device-info", "get-viewport-presets", "get-capabilities", "report-issue",
    "wait-for-element", "wait-for-navigation",
    "find-element", "find-button", "find-link", "find-input",
    "evaluate", "toast", "get-console-messages", "get-js-errors", "get-network-log",
    "get-resource-timeline", "get-websockets", "get-websocket-messages", "clear-console",
    "get-accessibility-tree", "screenshot-annotated", "click-annotation", "fill-annotation",
    "get-visible-elements", "get-page-text", "get-form-state",
    "get-dialog", "handle-dialog", "set-dialog-auto-handler",
    "get-tabs", "new-tab", "switch-tab", "close-tab",
    "get-iframes", "switch-to-iframe", "switch-to-main", "get-iframe-context",
    "get-cookies", "set-cookie", "delete-cookies",
    "get-storage", "set-storage", "clear-storage",
    "watch-mutations", "get-mutations", "stop-watching",
    "query-shadow-dom", "get-shadow-roots",
    "get-clipboard", "set-clipboard",
    "set-geolocation", "clear-geolocation",
    "set-request-interception", "get-intercepted-requests", "clear-request-interception",
    "show-keyboard", "hide-keyboard", "get-keyboard-state",
    "resize-viewport", "reset-viewport", "set-viewport-preset", "is-element-obscured",
    "safari-auth", "set-orientation", "get-orientation",
    "show-commentary", "hide-commentary", "highlight", "hide-highlight",
    "play-script", "abort-script", "get-script-status",
    "snapshot-3d-enter", "snapshot-3d-exit", "snapshot-3d-status", "snapshot-3d-set-mode", "snapshot-3d-zoom", "snapshot-3d-reset-view",
    "ai-status", "ai-load", "ai-unload", "ai-infer", "ai-record",
    "set-fullscreen", "get-fullscreen",
    "set-renderer", "get-renderer",
    "get-tap-calibration", "set-tap-calibration"
]
