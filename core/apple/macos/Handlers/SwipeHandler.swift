import Foundation

struct SwipeHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("swipe") { body in await swipe(body) }
    }

    @MainActor
    private func swipe(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        guard let from = body["from"] as? [String: Any],
              let to = body["to"] as? [String: Any],
              let fx = double(from["x"]),
              let fy = double(from["y"]),
              let tx = double(to["x"]),
              let ty = double(to["y"]) else {
            return errorResponse(code: "MISSING_PARAM", message: "from: {x,y} and to: {x,y} are required")
        }

        let durationMs = max(body["durationMs"] as? Int ?? 400, 1)
        let steps = max(body["steps"] as? Int ?? 20, 2)
        let color = body["color"] as? String ?? "#3B82F6"
        do {
            _ = try await context.evaluateJS(
                swipeTrailScript(
                    fx: fx,
                    fy: fy,
                    tx: tx,
                    ty: ty,
                    durationMs: durationMs,
                    color: color
                ),
                tabId: tabId
            )
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "WEBVIEW_ERROR", message: error.localizedDescription)
        }

        let stepDelay = max(durationMs / steps, 1)
        for step in 0...steps {
            if context.scriptPlaybackState?.isAbortRequested() == true { break }
            let progress = Double(step) / Double(steps)
            let currentX = fx + (tx - fx) * progress
            let currentY = fy + (ty - fy) * progress
            do {
                _ = try await context.evaluateJS(
                    pointerEventScript(
                        step: step,
                        totalSteps: steps,
                        x: currentX,
                        y: currentY
                    ),
                    tabId: tabId
                )
            } catch {
                if let tabError = tabErrorResponse(from: error) { return tabError }
                return errorResponse(code: "WEBVIEW_ERROR", message: error.localizedDescription)
            }
            if step < steps {
                try? await Task.sleep(nanoseconds: UInt64(stepDelay) * 1_000_000)
            }
        }

        return successResponse([
            "from": ["x": fx, "y": fy],
            "to": ["x": tx, "y": ty],
            "durationMs": durationMs,
            "steps": steps,
            "direction": swipeDirection(fromX: fx, fromY: fy, toX: tx, toY: ty)
        ])
    }

    private func double(_ value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        default:
            return nil
        }
    }

    private func swipeTrailScript(
        fx: Double,
        fy: Double,
        tx: Double,
        ty: Double,
        durationMs: Int,
        color: String
    ) -> String {
        """
        (function() {
            var existing = document.getElementById('__kelpie_swipe');
            if (existing) existing.remove();
            var root = document.createElement('div');
            root.id = '__kelpie_swipe';
            root.style.cssText = 'position:fixed;left:0;top:0;width:100%;height:100%;pointer-events:none;z-index:2147483647;';
            var trail = document.createElement('div');
            var length = Math.hypot(\(tx - fx), \(ty - fy));
            var angle = Math.atan2(\(ty - fy), \(tx - fx)) * 180 / Math.PI;
            trail.style.cssText = 'position:absolute;left:\(fx)px;top:\(fy)px;width:' + length + 'px;height:6px;' +
                'transform-origin:0 50%;transform:translateY(-50%) rotate(' + angle + 'deg);' +
                'background:linear-gradient(90deg,\(JSEscape.string(color)),transparent);border-radius:999px;opacity:0.65;';
            var dot = document.createElement('div');
            dot.style.cssText = 'position:absolute;left:\(fx)px;top:\(fy)px;width:26px;height:26px;margin-left:-13px;margin-top:-13px;' +
                'border-radius:50%;background:\(JSEscape.string(color));box-shadow:0 0 0 4px rgba(255,255,255,0.2);' +
                'transition:left \(durationMs)ms linear, top \(durationMs)ms linear;';
            root.appendChild(trail);
            root.appendChild(dot);
            document.body.appendChild(root);
            requestAnimationFrame(function() {
                dot.style.left = '\(tx)px';
                dot.style.top = '\(ty)px';
            });
            setTimeout(function() {
                root.style.transition = 'opacity 0.2s ease-out';
                root.style.opacity = '0';
                setTimeout(function() { root.remove(); }, 220);
            }, \(durationMs + 120));
        })();
        """
    }

    private func pointerEventScript(step: Int, totalSteps: Int, x: Double, y: Double) -> String {
        let eventType = step == 0 ? "pointerdown" : (step == totalSteps ? "pointerup" : "pointermove")
        return """
        (function() {
            var pointX = \(x);
            var pointY = \(y);
            var eventTarget = document.elementFromPoint(pointX, pointY) || document.body;
            if (window.PointerEvent) {
                eventTarget.dispatchEvent(new PointerEvent('\(eventType)', {
                    bubbles: true,
                    clientX: pointX,
                    clientY: pointY,
                    pointerId: 1,
                    pointerType: 'touch',
                    isPrimary: true
                }));
            }
        })();
        """
    }

    private func swipeDirection(fromX: Double, fromY: Double, toX: Double, toY: Double) -> String {
        let dx = toX - fromX
        let dy = toY - fromY

        if dy <= -100, abs(dx) < 50 {
            return "up"
        }
        if dy >= 100, abs(dx) < 50 {
            return "down"
        }
        if dx <= -100, abs(dy) < 50 {
            return "left"
        }
        if dx >= 100, abs(dy) < 50 {
            return "right"
        }
        return "diagonal"
    }
}
