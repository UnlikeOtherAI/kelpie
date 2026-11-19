import WebKit

/// Public page evaluation. Internal renderer scripts retain their synchronous API.
@MainActor
enum PageJavaScript {
    static func evaluate(_ source: String, in webView: WKWebView) async throws -> Any? {
        let wrapper = """
            const evaluate = globalThis.eval;
            try {
                evaluate("void 0");
            } catch (error) {
                // The page can prohibit string compilation. No user code has run.
                if (error instanceof EvalError) return { blocked: true };
                throw error;
            }
            let timer;
            try {
                const value = evaluate(source);
                if (typeof value?.then !== "function") return { value: value ?? null };
                const deadline = new Promise((_, reject) => {
                    timer = setTimeout(() => reject(new Error("JavaScript evaluation timed out")), 30000);
                });
                return { value: (await Promise.race([value, deadline])) ?? null };
            } catch (error) {
                return { error: String(error) };
            } finally {
                if (timer !== undefined) clearTimeout(timer);
            }
            """
        let reply = try await webView.callAsyncJavaScript(wrapper, arguments: ["source": source], in: nil, contentWorld: .page)
        guard let result = reply as? [String: Any] else {
            throw EvaluationError(message: "Invalid JavaScript evaluation result")
        }
        if result["blocked"] as? Bool == true {
            return try await webView.evaluateJavaScript(source)
        }
        if let message = result["error"] as? String {
            throw EvaluationError(message: message)
        }
        return result["value"]
    }

    private struct EvaluationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
