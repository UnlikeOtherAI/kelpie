import WebKit

/// Handles evaluate and wait endpoints.
struct EvaluateHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("evaluate") { body in await evaluate(body) }
        router.register("wait-for-element") { body in await waitForElement(body) }
        router.register("wait-for-navigation") { body in await waitForNavigation(body) }
    }

    @MainActor
    private func evaluate(_ body: [String: Any]) async -> [String: Any] {
        guard let expression = body["expression"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "expression is required")
        }
        do {
            let result = try await context.evaluateJS(expression)
            return successResponse(["result": result ?? NSNull()])
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func waitForElement(_ body: [String: Any]) async -> [String: Any] {
        guard let selector = body["selector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let timeout = body["timeout"] as? Int ?? 5000
        let state = body["state"] as? String ?? "visible"
        let start = CFAbsoluteTimeGetCurrent()
        let iterations = timeout / 100

        for _ in 0..<iterations {
            let js = """
            (function() {
                var el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
                if (!el) return null;
                var rect = el.getBoundingClientRect();
                var visible = rect.width > 0 && rect.height > 0;
                return {tag: el.tagName.toLowerCase(), classes: Array.from(el.classList), visible: visible};
            })()
            """
            if let result = try? await context.evaluateJSReturningJSON(js), !result.isEmpty {
                let visible = result["visible"] as? Bool ?? false
                let matches = (state == "attached") || (state == "visible" && visible) || (state == "hidden" && !visible)
                if matches {
                    let waitTime = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    return successResponse(["element": result, "waitTime": waitTime])
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return errorResponse(code: "TIMEOUT", message: "Element did not reach state '\(state)' within \(timeout)ms")
    }

    @MainActor
    private func waitForNavigation(_ body: [String: Any]) async -> [String: Any] {
        guard let webView = context.webView else { return errorResponse(code: "NO_WEBVIEW", message: "No WebView") }
        let timeout = body["timeout"] as? Int ?? 10000
        let start = CFAbsoluteTimeGetCurrent()

        for _ in 0..<(timeout / 100) {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !webView.isLoading {
                let loadTime = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                return successResponse(["url": webView.url?.absoluteString ?? "", "title": webView.title ?? "", "loadTime": loadTime])
            }
        }
        return errorResponse(code: "TIMEOUT", message: "Navigation did not complete within \(timeout)ms")
    }
}
