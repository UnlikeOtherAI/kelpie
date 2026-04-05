import WebKit

/// Handles scroll, scroll2, scrollToTop, scrollToBottom.
struct ScrollHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("scroll") { body in await scroll(body) }
        router.register("scroll2") { body in await scroll2(body) }
        router.register("scroll-to-top") { _ in await scrollTo(top: true) }
        router.register("scroll-to-bottom") { _ in await scrollTo(top: false) }
    }

    @MainActor
    private func scroll(_ body: [String: Any]) async -> [String: Any] {
        let dx = body["deltaX"] as? Double ?? 0
        let dy = body["deltaY"] as? Double ?? 0
        let js = "window.scrollBy(\(dx), \(dy)); ({scrollX: window.scrollX, scrollY: window.scrollY})"
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func scroll2(_ body: [String: Any]) async -> [String: Any] {
        guard let selector = body["selector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let position = body["position"] as? String ?? "center"
        let maxScrolls = body["maxScrolls"] as? Int ?? 10
        let js = """
        (function() {
            var el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
            if (!el) return null;
            el.scrollIntoView({block: '\(position)', behavior: 'smooth'});
            var rect = el.getBoundingClientRect();
            return {element: {tag: el.tagName.toLowerCase(), visible: rect.top >= 0 && rect.bottom <= window.innerHeight, rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height}}, scrollsPerformed: 1, viewport: {width: window.innerWidth, height: window.innerHeight}};
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            if result.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(selector)") }
            await context.showTouchIndicatorForElement(selector)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func scrollTo(top: Bool) async -> [String: Any] {
        let js = top
            ? "window.scrollTo(0, 0); ({scrollY: 0})"
            : "window.scrollTo(0, document.documentElement.scrollHeight); ({scrollY: window.scrollY})"
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }
}
