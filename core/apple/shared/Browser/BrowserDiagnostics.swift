import Foundation

/// Diagnostics belong to the renderer that emitted them, even while its tab is in the background.
@MainActor
final class BrowserDiagnostics {
    private static let buffers = NSMapTable<AnyObject, BrowserDiagnostics>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory
    )

    static func forTarget(_ owner: AnyObject) -> BrowserDiagnostics {
        if let buffer = buffers.object(forKey: owner) { return buffer }
        let buffer = BrowserDiagnostics()
        buffers.setObject(buffer, forKey: owner)
        return buffer
    }

    var console: [[String: Any]] = []
    private(set) var network: [[String: Any]] = []
    var documentResponse: (url: String, status: Int, mimeType: String)?

    func recordConsole(_ message: [String: Any]) {
        if message["text"] as? String == "__kelpie_3d_exit__" ||
            message["message"] as? String == "__kelpie_3d_exit__" { return }
        console.append(message)
        if console.count > 5000 { console.removeFirst() }
    }

    func recordNetwork(_ event: [String: Any]) {
        // Retain request metadata only. Bodies and headers stay in the existing inspector.
        let metadata: Set<String> = [
            "method", "url", "type", "statusCode", "statusText", "contentType",
            "started", "duration", "size", "failure"
        ]
        network.append(event.filter { metadata.contains($0.key) })
        if network.count > 2000 { network.removeFirst() }
    }
}

struct DiagnosticTarget {
    let buffer: BrowserDiagnostics
    let evaluate: @MainActor (String) async throws -> Any?
}

enum DiagnosticError: Error {
    case tabNotFound(String)
}

func diagnosticErrorResponse(_ error: Error) -> [String: Any] {
    if let error = error as? DiagnosticError, case .tabNotFound(let id) = error {
        return errorResponse(code: "TAB_NOT_FOUND", message: "No tab with id \(id)")
    }
    #if os(macOS)
    if let response = tabErrorResponse(from: error) { return response }
    #endif
    return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
}
