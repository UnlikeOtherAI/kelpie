import WebKit

// swiftlint:disable line_length

/// Handles DOM queries: getDOM, querySelector, querySelectorAll, getElementText, getAttributes.
struct DOMHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("get-links") { body in await getLinks(body) }
        router.register("get-dom") { body in await getDOM(body) }
        router.register("query-selector") { body in await querySelector(body) }
        router.register("query-selector-all") { body in await querySelectorAll(body) }
        router.register("get-element-text") { body in await getElementText(body) }
        router.register("get-attributes") { body in await getAttributes(body) }
    }

    @MainActor
    private func getLinks(_ body: [String: Any]) async -> [String: Any] {
        do {
            let result = try await context.evaluateJSReturningJSON(
                """
                (() => {
                    const links = Array.from(document.querySelectorAll('a[href]'));
                    return {count: links.length, links: links.slice(0, 200).map(link => ({
                        href: link.href, text: (link.textContent || '').trim().substring(0, 200)
                    }))};
                })()
                """, windowId: HandlerContext.windowId(from: body), tabId: HandlerContext.tabId(from: body)
            )
            return successResponse(result)
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func getDOM(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        let selector = body["selector"] as? String ?? "html"
        let js = """
        (function() {
            var el = document.querySelector('\(JSEscape.string(selector))');
            if (!el) return {found: false};
            return {found: true, html: el.outerHTML, nodeCount: el.querySelectorAll('*').length + 1};
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js, tabId: tabId)
            guard result["found"] as? Bool == true else {
                return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Selector not found: \(selector)")
            }
            return successResponse(["html": result["html"] ?? "", "nodeCount": result["nodeCount"] ?? 0])
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func querySelector(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        guard let selector = body["selector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let js = """
        (function() {
            var el = document.querySelector('\(JSEscape.string(selector))');
            if (!el) return {found: false};
            var rect = el.getBoundingClientRect();
            return {found: true, element: {tag: el.tagName.toLowerCase(), id: el.id || undefined, text: (el.textContent || '').trim().substring(0, 200), classes: Array.from(el.classList), rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height}, visible: rect.width > 0 && rect.height > 0}};
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js, tabId: tabId)
            return successResponse(result)
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func querySelectorAll(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        guard let selector = body["selector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let js = """
        (function() {
            var els = document.querySelectorAll('\(JSEscape.string(selector))');
            return {count: els.length, elements: Array.from(els).slice(0, 100).map(function(el) {
                var rect = el.getBoundingClientRect();
                return {tag: el.tagName.toLowerCase(), id: el.id || undefined, text: (el.textContent || '').trim().substring(0, 200), rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height}};
            })};
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js, tabId: tabId)
            return successResponse(result)
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func getElementText(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        guard let selector = body["selector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let js = "(document.querySelector('\(JSEscape.string(selector))')?.textContent || '')"
        do {
            let text = try await context.evaluateJSReturningString(js, tabId: tabId)
            return successResponse(["text": text.trimmingCharacters(in: .whitespacesAndNewlines)])
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(selector)")
        }
    }

    @MainActor
    private func getAttributes(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        guard let selector = body["selector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let js = """
        (function() {
            var el = document.querySelector('\(JSEscape.string(selector))');
            if (!el) return null;
            var attrs = {};
            for (var i = 0; i < el.attributes.length; i++) attrs[el.attributes[i].name] = el.attributes[i].value;
            return {attributes: attrs};
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js, tabId: tabId)
            if result.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(selector)") }
            return successResponse(result)
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }
}
