import Foundation

/// Route handler receives parsed JSON body and returns a JSON-serializable response.
typealias RouteHandler = @Sendable ([String: Any]) async -> [String: Any]

/// Maps POST /v1/{method} paths to handler functions.
final class Router: @unchecked Sendable {
    private var routes: [String: RouteHandler] = [:]
    var handlerContext: HandlerContext?

    func register(_ method: String, handler: @escaping RouteHandler) {
        routes[method] = handler
    }

    func handle(method: String, body: [String: Any]) async -> (statusCode: Int, json: [String: Any]) {
        guard let handler = routes[method] else {
            return (404, [
                "success": false,
                "error": ["code": "NOT_FOUND", "message": "Unknown method: \(method)"],
            ])
        }
        let result = await handler(body)
        let success = result["success"] as? Bool ?? false
        let status = success ? 200 : (result["error"] != nil ? 400 : 200)

        // Auto-show toast if the request includes a "message" param
        if let message = body["message"] as? String, !message.isEmpty, let ctx = handlerContext {
            await ctx.showToast(message)
        }

        return (status, result)
    }

    /// Registers stub handlers for all API methods (to be replaced in Task 11).
    func registerStubs() {
        let methods = [
            "navigate", "back", "forward", "reload", "get-current-url",
            "screenshot", "get-dom", "query-selector", "query-selector-all",
            "get-element-text", "get-attributes", "click", "tap", "fill",
            "type", "select-option", "check", "uncheck", "scroll", "scroll2",
            "scroll-to-top", "scroll-to-bottom", "get-viewport", "get-device-info",
            "get-capabilities", "wait-for-element", "wait-for-navigation",
            "find-element", "find-button", "find-link", "find-input",
            "evaluate", "get-console-messages", "get-js-errors",
            "get-network-log", "get-resource-timeline", "clear-console",
            "get-accessibility-tree", "screenshot-annotated", "click-annotation",
            "fill-annotation", "get-visible-elements", "get-page-text",
            "get-form-state", "get-dialog", "handle-dialog",
            "set-dialog-auto-handler", "get-tabs", "new-tab", "switch-tab",
            "close-tab", "get-iframes", "switch-to-iframe", "switch-to-main",
            "get-iframe-context", "get-cookies", "set-cookie", "delete-cookies",
            "get-storage", "set-storage", "clear-storage", "watch-mutations",
            "get-mutations", "stop-watching", "query-shadow-dom",
            "get-shadow-roots", "get-clipboard", "set-clipboard",
            "set-geolocation", "clear-geolocation", "set-request-interception",
            "get-intercepted-requests", "clear-request-interception",
            "show-keyboard", "hide-keyboard", "get-keyboard-state",
            "resize-viewport", "reset-viewport", "is-element-obscured",
            "toast", "safari-auth",
            "set-orientation", "get-orientation",
        ]
        for method in methods {
            if routes[method] == nil {
                register(method) { _ in
                    ["success": false, "error": ["code": "NOT_IMPLEMENTED", "message": "\(method) not yet implemented"]]
                }
            }
        }
    }
}
