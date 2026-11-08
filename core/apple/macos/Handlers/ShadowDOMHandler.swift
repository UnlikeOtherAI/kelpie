import WebKit

/// Handles queryShadowDOM and getShadowRoots.
struct ShadowDOMHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("query-shadow-dom") { body in await queryShadowDOM(body) }
        router.register("get-shadow-roots") { body in await getShadowRoots(body) }
    }

    @MainActor
    private func queryShadowDOM(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        guard let hostSelector = body["hostSelector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "hostSelector is required")
        }
        let shadowSelector = body["shadowSelector"] as? String ?? "*"
        let pierce = body["pierce"] as? Bool ?? true
        let safeHost = JSEscape.string(hostSelector)
        let safeShadow = JSEscape.string(shadowSelector)

        let js = """
        (function(){
            function findInShadow(host, sel, recurse) {
                if (!host || !host.shadowRoot) return null;
                var el = host.shadowRoot.querySelector(sel);
                if (el) return el;
                if (recurse) {
                    var all = host.shadowRoot.querySelectorAll('*');
                    for (var i = 0; i < all.length; i++) {
                        if (all[i].shadowRoot) {
                            var found = findInShadow(all[i], sel, true);
                            if (found) return found;
                        }
                    }
                }
                return null;
            }
            var host = document.querySelector('\(safeHost)');
            if (!host) return {found: false, error: 'Host element not found'};
            var el = findInShadow(host, '\(safeShadow)', \(pierce));
            if (!el) return {found: false};
            var r = el.getBoundingClientRect();
            var tag = el.tagName.toLowerCase();
            return {
                found: true,
                element: {
                    tag: tag,
                    text: (el.textContent || '').trim().substring(0, 100),
                    shadowHost: '\(safeHost)',
                    rect: {x: r.x, y: r.y, width: r.width, height: r.height},
                    visible: r.width > 0 && r.height > 0,
                    interactable: ['a','button','input','select','textarea'].includes(tag)
                }
            };
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
    private func getShadowRoots(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        let js = """
        (function(){
            var hosts = [];
            var all = document.querySelectorAll('*');
            for (var i = 0; i < all.length; i++) {
                var el = all[i];
                if (el.shadowRoot) {
                    var tag = el.tagName.toLowerCase();
                    hosts.push({
                        selector: tag + (el.id ? '#' + el.id : ''),
                        tag: tag,
                        mode: 'open',
                        childCount: el.shadowRoot.childElementCount
                    });
                }
            }
            return {hosts: hosts, count: hosts.length};
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
}
