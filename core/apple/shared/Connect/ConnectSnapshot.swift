import Foundation

/// Fixed shared reader, registered only in the job-owned router.
@MainActor
final class ConnectSnapshot {
    private let context: HandlerContext
    init(context: HandlerContext) { self.context = context }

    func register(on router: Router) {
        router.register("connect-snapshot") { [self] body in
            do {
                try Task.checkCancellation()
                if context.remoteDocumentGuard?() == false { throw CancellationError() }
                let options: [String: Any] = [
                    "prefix": "observed", "maxElements": 150,
                    "maxChars": max(64, min(16000, body["maxChars"] as? Int ?? 16000)), "includeShadow": false]
                let data = try JSONSerialization.data(withJSONObject: options)
                guard let raw = String(data: data, encoding: .utf8) else { throw CancellationError() }
                guard let pointer = raw.withCString({ kelpie_browser_selector_snapshot_expression($0) }) else {
                    throw CancellationError()
                }
                defer { kelpie_mcp_free_string(pointer) }
                let generated = try JSONSerialization.jsonObject(with: Data(String(cString: pointer).utf8)) as? [String: Any]
                guard let expression = generated?["expression"] as? String else { throw CancellationError() }
                #if os(iOS)
                guard let view = context.webView else { throw CancellationError() }
                let value = try await BrowserControlWebKit.evaluate(expression, in: view)
                #else
                let renderer = try context.resolveRenderer(windowId: nil, tabId: body["tabId"] as? String)
                let value = try await renderer.evaluateBrowserControlJS(expression)
                #endif
                try Task.checkCancellation()
                if context.remoteDocumentGuard?() == false { throw CancellationError() }
                guard let snapshot = value as? [String: Any] else { throw CancellationError() }
                return successResponse(snapshot)
            } catch {
                return errorResponse(code: "SNAPSHOT_UNAVAILABLE", message: "Pinned page snapshot unavailable")
            }
        }
    }
}
