import Foundation

/// Route handler receives parsed JSON body and returns a JSON-serializable response.
typealias RouteHandler = @Sendable ([String: Any]) async -> [String: Any]

/// Maps POST /v1/{method} paths to handler functions.
final class Router: @unchecked Sendable {
    private var routes: [String: RouteHandler] = [:]
    var handlerContext: HandlerContext?
    var scriptPlaybackState: ScriptPlaybackState?

    func register(_ method: String, handler: @escaping RouteHandler) {
        routes[method] = handler
    }

    func handle(
        method: String,
        body: [String: Any],
        bypassRecordingGate: Bool = false
    ) async -> (statusCode: Int, json: [String: Any]) {
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
}

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
