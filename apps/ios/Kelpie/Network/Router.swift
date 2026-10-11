import Foundation

/// Route handler receives parsed JSON body and returns a JSON-serializable response.
typealias RouteHandler = @MainActor @Sendable ([String: Any]) async -> [String: Any]

/// Maps POST /v1/{method} paths to handler functions.
final class Router: @unchecked Sendable {
    private var routes: [String: RouteHandler] = [:]
    var handlerContext: HandlerContext?
    var scriptPlaybackState: ScriptPlaybackState?
    @MainActor var browserGateway: BrowserControlGateway?
    @MainActor var browserGatewayProfile: String?
    let browserLease = BrowserControlLease()
    @MainActor var browserGateways: [WeakBrowserGateway] = []
    var registeredMethods: [String] { Array(routes.keys) }

    func register(_ method: String, handler: @escaping RouteHandler) {
        routes[method] = handler
    }

    func registerIfAbsent(_ method: String, handler: @escaping RouteHandler) {
        guard routes[method] == nil else { return }
        routes[method] = handler
    }

    @MainActor
    func handle(
        method: String,
        body: [String: Any],
        bypassRecordingGate: Bool = false,
        browserGatewayDispatch: Bool = false
    ) async -> (statusCode: Int, json: [String: Any]) {
        if method == "browser-control" {
            return (200, await browserControl(body))
        }
        let mutatingMethod = isBrowserMutation(method: method)
        let legacyMutation = !browserGatewayDispatch && !bypassRecordingGate && mutatingMethod
        if legacyMutation, browserLease.begin() == false {
            return (409, errorResponse(code: "BUSY", message: "A browser operation is pending"))
        }
        defer { if legacyMutation { browserLease.end() } }
        invalidateBrowserReferences(method: method, body: body)
        guard let handler = routes[method] else {
            return (404, [
                "success": false,
                "error": ["code": "NOT_FOUND", "message": "Unknown method: \(method)"]
            ])
        }
        if !bypassRecordingGate, let gateError = scriptPlaybackState?.recordingError(for: method) {
            return (409, gateError)
        }
        let result = await handler(body)
        let success = result["success"] as? Bool ?? false
        let errorCode = (result["error"] as? [String: Any])?["code"] as? String
        let status: Int
        if success {
            status = 200
        } else if errorCode == "SCRIPT_PARTIAL_FAILURE" || errorCode == "SCRIPT_ABORTED" {
            status = 200
        } else if result["error"] != nil {
            status = statusCode(forErrorCode: errorCode)
        } else {
            status = 200
        }

        // Auto-show toast if the request includes a "message" param
        if let message = body["message"] as? String, !message.isEmpty, let ctx = handlerContext {
            await ctx.showToast(message)
        }

        return (status, result)
    }

    func registerFallbacks() {
        let methods = [
            "set-geolocation", "clear-geolocation", "set-request-interception",
            "get-intercepted-requests", "clear-request-interception"
        ]
        for method in methods {
            let unsupported = iosUnsupportedMethods.contains(method)
            registerIfAbsent(method) { _ in
                [
                    "success": false,
                    "error": [
                        "code": unsupported ? "PLATFORM_NOT_SUPPORTED" : "NOT_IMPLEMENTED",
                        "message": unsupported ? "\(method) is not supported on iOS" : "\(method) not yet implemented"
                    ]
                ]
            }
        }
    }
}

private let iosUnsupportedMethods: Set<String> = [
    "set-geolocation", "clear-geolocation",
    "set-request-interception", "get-intercepted-requests", "clear-request-interception",
    "set-fullscreen", "get-fullscreen",
    "set-renderer", "get-renderer"
]

private func statusCode(forErrorCode code: String?) -> Int {
    switch code {
    case "ELEMENT_NOT_FOUND", "WATCH_NOT_FOUND":
        return 404
    case "TIMEOUT":
        return 408
    case "NAVIGATION_ERROR":
        return 502
    case "PLATFORM_NOT_SUPPORTED":
        return 501
    case "IFRAME_ACCESS_DENIED", "PERMISSION_REQUIRED", "SHADOW_ROOT_CLOSED":
        return 403
    case "RECORDING_IN_PROGRESS":
        return 409
    case "WEBVIEW_ERROR":
        return 500
    default:
        return 400
    }
}
