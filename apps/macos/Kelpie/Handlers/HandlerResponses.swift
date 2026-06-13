import Foundation

extension Notification.Name {
    static let snapshot3DExited = Notification.Name("kelpie.snapshot3DExited")
}

enum HandlerError: Error {
    case noWebView
    case rendererHidden
    case elementNotFound(String)
    case screenshotFailed
    case timeout
    case platformNotSupported(String)
    case tabNotFound(String)
    case tabRequired(String)
    case windowNotFound(String)
}

func tabErrorResponse(from error: Error) -> [String: Any]? {
    guard let handlerError = error as? HandlerError else { return nil }
    switch handlerError {
    case .tabNotFound(let tabId):
        return errorResponse(code: "TAB_NOT_FOUND", message: "No tab with id \"\(tabId)\"")
    case .tabRequired(let listing):
        return errorResponse(
            code: "TAB_REQUIRED",
            message: "Multiple tabs open — specify \"tabId\" in your request. Available tabs:\n\(listing)"
        )
    case .windowNotFound(let windowId):
        return errorResponse(
            code: "WINDOW_NOT_FOUND",
            message: "No window with id \"\(windowId)\". Call get-tabs without windowId to list available windows."
        )
    case .rendererHidden:
        return errorResponse(
            code: "RENDERER_HIDDEN",
            message: "The active renderer is hidden — its view is detached or off-screen, " +
                "so script evaluation and DOM queries are unavailable. Bring the window " +
                "to front or switch to a renderer whose view is visible."
        )
    default:
        return nil
    }
}

func errorResponse(code: String, message: String) -> [String: Any] {
    errorResponse(code: code, message: message, diagnostics: nil)
}

func errorResponse(code: String, message: String, diagnostics: [String: Any]?) -> [String: Any] {
    var error: [String: Any] = ["code": code, "message": message]
    if let diagnostics, !diagnostics.isEmpty {
        error["diagnostics"] = diagnostics
    }
    return ["success": false, "error": error]
}

func successResponse(_ data: [String: Any] = [:]) -> [String: Any] {
    var result: [String: Any] = ["success": true]
    for (key, value) in data { result[key] = value }
    return result
}
