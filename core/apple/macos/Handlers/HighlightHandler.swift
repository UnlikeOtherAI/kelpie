import Foundation

struct HighlightHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("highlight") { body in await highlight(body) }
        router.register("hide-highlight") { body in await hideHighlight(body) }
    }

    @MainActor
    private func highlight(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        guard let selector = body["selector"] as? String, !selector.isEmpty else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let color = body["color"] as? String ?? "#EF4444"
        let thickness = body["thickness"] as? Int ?? 2
        let padding = body["padding"] as? Int ?? 4
        let animation = body["animation"] as? String ?? "appear"
        let durationMs = body["durationMs"] as? Int ?? 2000

        do {
            let result = try await context.evaluateJSReturningString(
                highlightScript(
                    selector: selector,
                    color: color,
                    thickness: thickness,
                    padding: padding,
                    animation: animation,
                    durationMs: durationMs
                ),
                tabId: tabId
            )
            guard let data = result.data(using: .utf8),
                  let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(selector)")
            }
            return successResponse(parsed)
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func hideHighlight(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        let js = """
        (function() {
            var el = document.getElementById('__kelpie_highlight');
            if (!el) return;
            el.style.opacity = '0';
            setTimeout(function() { el.remove(); }, 250);
        })();
        """
        _ = try? await context.evaluateJS(js, tabId: tabId)
        return successResponse()
    }

    private func highlightScript(
        selector: String,
        color: String,
        thickness: Int,
        padding: Int,
        animation: String,
        durationMs: Int
    ) -> String {
        let dismissJS = durationMs > 0 ? """
            setTimeout(function() {
                root.style.opacity = '0';
                setTimeout(function() { root.remove(); }, 250);
            }, \(durationMs));
        """ : ""

        return """
        (function() {
            var existing = document.getElementById('__kelpie_highlight');
            if (existing) existing.remove();
            var el = document.querySelector('\(JSEscape.string(selector))');
            if (!el) return JSON.stringify(null);

            var rect = el.getBoundingClientRect();
            var left = rect.left + window.scrollX - \(padding);
            var top = rect.top + window.scrollY - \(padding);
            var width = rect.width + \(padding * 2);
            var height = rect.height + \(padding * 2);

            var root = document.createElement('div');
            root.id = '__kelpie_highlight';
            root.style.cssText = 'position:absolute;left:' + left + 'px;top:' + top + 'px;' +
                'width:' + width + 'px;height:' + height + 'px;pointer-events:none;' +
                'z-index:2147483647;opacity:0;transition:opacity 0.15s ease-out;';

            if ('\(JSEscape.string(animation))' === 'draw') {
                var svgNS = 'http://www.w3.org/2000/svg';
                var svg = document.createElementNS(svgNS, 'svg');
                svg.setAttribute('width', width);
                svg.setAttribute('height', height);
                svg.setAttribute('viewBox', '0 0 ' + width + ' ' + height);
                var rectNode = document.createElementNS(svgNS, 'rect');
                rectNode.setAttribute('x', '1');
                rectNode.setAttribute('y', '1');
                rectNode.setAttribute('width', Math.max(width - 2, 1));
                rectNode.setAttribute('height', Math.max(height - 2, 1));
                rectNode.setAttribute('rx', '8');
                rectNode.setAttribute('ry', '8');
                rectNode.setAttribute('fill', 'none');
                rectNode.setAttribute('stroke', '\(JSEscape.string(color))');
                rectNode.setAttribute('stroke-width', '\(thickness)');
                var perimeter = Math.max((width + height) * 2 - 8, 1);
                rectNode.style.strokeDasharray = String(perimeter);
                rectNode.style.strokeDashoffset = String(perimeter);
                rectNode.style.transition = 'stroke-dashoffset 0.6s ease-out';
                svg.appendChild(rectNode);
                root.appendChild(svg);
                document.body.appendChild(root);
                requestAnimationFrame(function() {
                    root.style.opacity = '1';
                    rectNode.style.strokeDashoffset = '0';
                });
            } else {
                root.style.border = '\(thickness)px solid \(JSEscape.string(color))';
                root.style.borderRadius = '8px';
                document.body.appendChild(root);
                requestAnimationFrame(function() { root.style.opacity = '1'; });
            }

            \(dismissJS)
            return JSON.stringify({
                selector: '\(JSEscape.string(selector))',
                rect: {x: left, y: top, width: width, height: height},
                color: '\(JSEscape.string(color))'
            });
        })();
        """
    }
}
