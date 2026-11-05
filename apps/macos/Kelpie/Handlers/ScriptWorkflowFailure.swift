import Foundation

/// Public workflow diagnostics never forward renderer/page/provider exception text.
struct ScriptWorkflowFailure: LocalizedError {
    let code: String
    let mayHaveCompleted: Bool

    init(_ code: String, mayHaveCompleted: Bool = false) {
        self.code = code
        self.mayHaveCompleted = mayHaveCompleted
    }

    var errorDescription: String? { "Workflow stopped at its last confirmed step" }
    var response: [String: Any] {
        var value = errorResponse(code: code, message: errorDescription ?? "Workflow stopped")
        if mayHaveCompleted { value["mayHaveCompleted"] = true }
        return value
    }
}
