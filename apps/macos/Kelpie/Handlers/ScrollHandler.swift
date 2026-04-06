import WebKit

// swiftlint:disable line_length

/// Handles scroll, scroll2, scrollToTop, scrollToBottom, scrollToY.
///
/// Every scroll operation also syncs `window.__m3d.scrollX/Y` when the 3D
/// inspector is active so that exiting the inspector restores to the
/// currently-visible position rather than the enter-time snapshot.
struct ScrollHandler {
    let context: HandlerContext

    /// JS fragment that syncs the 3D inspector's stored scroll state with the
    /// live `window.scrollX/Y`. A no-op when the inspector isn't active.
    private static let sync3DStateJS = """
    if (window.__m3d) {
        window.__m3d.scrollX = window.scrollX;
        window.__m3d.scrollY = window.scrollY;
    }
    """

    func register(on router: Router) {
        router.register("scroll") { body in await scroll(body) }
        router.register("scroll2") { body in await scroll2(body) }
        router.register("scroll-to-top") { _ in await scrollTo(top: true) }
        router.register("scroll-to-bottom") { _ in await scrollTo(top: false) }
        router.register("scroll-to-y") { body in await scrollToY(body) }
    }

    @MainActor
    private func scroll(_ body: [String: Any]) async -> [String: Any] {
        let dx = body["deltaX"] as? Double ?? 0
        let dy = body["deltaY"] as? Double ?? 0
        let js = """
        (function() {
            window.scrollBy(\(dx), \(dy));
            \(Self.sync3DStateJS)
            return {scrollX: window.scrollX, scrollY: window.scrollY};
        })()
        """
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
            var el = document.querySelector('\(JSEscape.string(selector))');
            if (!el) return null;
            el.scrollIntoView({block: '\(position)', behavior: 'smooth'});
            \(Self.sync3DStateJS)
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
        let targetY = top ? "0" : "document.documentElement.scrollHeight"
        let js = """
        (function() {
            window.scrollTo(0, \(targetY));
            \(Self.sync3DStateJS)
            return {scrollX: window.scrollX, scrollY: window.scrollY};
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func scrollToY(_ body: [String: Any]) async -> [String: Any] {
        guard let y = body["y"] as? Double else {
            return errorResponse(code: "MISSING_PARAM", message: "y is required (pixel offset)")
        }
        let x = body["x"] as? Double ?? 0
        let js = """
        (function() {
            window.scrollTo(\(x), \(y));
            \(Self.sync3DStateJS)
            return {
                scrollX: window.scrollX,
                scrollY: window.scrollY,
                maxScrollY: Math.max(0, document.documentElement.scrollHeight - window.innerHeight)
            };
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }
}
