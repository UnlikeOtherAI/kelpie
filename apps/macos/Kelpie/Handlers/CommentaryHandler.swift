import Foundation

struct CommentaryHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("show-commentary") { body in await showCommentary(body) }
        router.register("hide-commentary") { _ in await hideCommentary() }
    }

    @MainActor
    private func showCommentary(_ body: [String: Any]) async -> [String: Any] {
        guard let text = body["text"] as? String, !text.isEmpty else {
            return errorResponse(code: "MISSING_PARAM", message: "text is required")
        }
        let durationMs = body["durationMs"] as? Int ?? 3000
        let position = body["position"] as? String ?? "bottom"

        let positionCSS: String
        switch position {
        case "top":
            positionCSS = "top:24px;left:50%;transform:translateX(-50%);"
        case "center":
            positionCSS = "top:50%;left:50%;transform:translate(-50%,-50%);"
        default:
            positionCSS = "bottom:24px;left:50%;transform:translateX(-50%);"
        }

        let autoDismiss = durationMs > 0 ? """
            setTimeout(function() {
                toast.style.opacity = '0';
                setTimeout(function() { toast.remove(); }, 300);
            }, \(durationMs));
        """ : ""

        let js = """
        (function() {
            var existing = document.getElementById('__kelpie_commentary');
            if (existing) existing.remove();
            var toast = document.createElement('div');
            toast.id = '__kelpie_commentary';
            toast.textContent = '\(JSEscape.string(text))';
            toast.style.cssText = 'position:fixed;\(positionCSS)' +
                'max-width:390px;width:calc(100% - 32px);padding:14px 22px;border-radius:16px;' +
                'background:rgba(0,0,0,0.5);color:#fff;font:15px/1.4 -apple-system,system-ui,sans-serif;' +
                'text-align:center;pointer-events:none;z-index:2147483647;' +
                'backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);' +
                'transition:opacity 0.3s ease-out;opacity:0;';
            document.body.appendChild(toast);
            requestAnimationFrame(function() { toast.style.opacity = '1'; });
            \(autoDismiss)
        })();
        """
        do {
            _ = try await context.evaluateJS(js)
            return successResponse([
                "text": text,
                "position": position,
                "durationMs": durationMs
            ])
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func hideCommentary() async -> [String: Any] {
        let js = """
        (function() {
            var el = document.getElementById('__kelpie_commentary');
            if (!el) return;
            el.style.opacity = '0';
            setTimeout(function() { el.remove(); }, 300);
        })();
        """
        _ = try? await context.evaluateJS(js)
        return successResponse()
    }
}
