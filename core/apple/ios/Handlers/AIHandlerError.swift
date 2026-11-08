import Foundation

struct AIHandlerError: Error {
    let code: String
    let message: String

    var response: [String: Any] {
        errorResponse(code: code, message: message)
    }
}
