# Scripted Video Recording — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `play-script`, `swipe`, `highlight`, and `commentary` endpoints to iOS and macOS, with CLI commands and MCP tools, enabling LLM-scripted video recording with visual overlays.

**Architecture:** New Swift handler structs (SwipeHandler, HighlightHandler, CommentaryHandler, ScriptHandler) following the existing `struct + HandlerContext + Router.register` pattern. Overlays are injected as ephemeral JS/CSS into the WebView DOM. The ScriptHandler orchestrates playback by delegating to existing handlers. CLI gets new commands that POST to device endpoints. MCP server gets new tool registrations.

**Tech Stack:** Swift (iOS/macOS handlers), TypeScript (CLI/MCP), Zod (MCP schemas), WebKit `evaluateJavaScript` (overlay injection)

**Design doc:** `docs/plans/2026-04-06-scripted-video-recording.md` — the authoritative spec. Read it before starting any task.

---

## Task Dependency Graph

```
Task 1 (overlay color)  ─┐
Task 2 (commentary)     ─┤
Task 3 (swipe)          ─┤─→ Task 6 (ScriptHandler) → Task 8 (CLI) → Task 9 (MCP) → Task 10 (docs)
Task 4 (highlight)      ─┤
Task 5 (fill mode)      ─┘
Task 7 (recording mode) ─┘
```

Tasks 1-5 are independent and can run in parallel. Task 6 depends on all of 1-5. Task 7 can run in parallel with 6. Tasks 8-10 are sequential.

---

## Task 1: Add Color Parameter to Touch Indicator

**Files:**
- Modify: `apps/ios/Kelpie/Handlers/HandlerContext.swift` (lines 69-98)
- Modify: `apps/macos/Kelpie/Handlers/HandlerContext.swift` (equivalent lines)

**Step 1: Modify `showTouchIndicator` to accept a color parameter**

In `HandlerContext.swift` on iOS, change the signature and body:

```swift
/// Show a touch indicator at viewport coordinates with a ripple animation.
func showTouchIndicator(x: Double, y: Double, color: String = "59,130,246") async {
    let js = """
    (function() {
        var dot = document.createElement('div');
        dot.style.cssText = 'position:fixed;left:\(x)px;top:\(y)px;width:36px;height:36px;' +
            'margin-left:-18px;margin-top:-18px;border-radius:50%;' +
            'background:rgba(\(JSEscape.string(color)),0.7);pointer-events:none;z-index:2147483647;' +
            'transition:transform 0.5s ease-out, opacity 0.5s ease-out;transform:scale(1);opacity:1;';
        document.body.appendChild(dot);
        var ripple = document.createElement('div');
        ripple.style.cssText = 'position:fixed;left:\(x)px;top:\(y)px;width:36px;height:36px;' +
            'margin-left:-18px;margin-top:-18px;border-radius:50%;' +
            'border:2px solid rgba(\(JSEscape.string(color)),0.7);pointer-events:none;z-index:2147483647;' +
            'transition:transform 0.6s ease-out, opacity 0.6s ease-out;transform:scale(1);opacity:1;';
        document.body.appendChild(ripple);
        requestAnimationFrame(function() {
            ripple.style.transform = 'scale(3)';
            ripple.style.opacity = '0';
        });
        setTimeout(function() {
            dot.style.transform = 'scale(0.5)';
            dot.style.opacity = '0';
        }, 550);
        setTimeout(function() {
            dot.remove();
            ripple.remove();
        }, 1100);
    })();
    """
    try? await evaluateJS(js)
}
```

The color parameter is RGB components (e.g. `"59,130,246"`) to drop straight into `rgba()`. The default matches the existing blue.

**Step 2: Update `showTouchIndicatorForElement` to pass color through**

```swift
func showTouchIndicatorForElement(_ selector: String, color: String = "59,130,246") async {
    // ... existing getBoundingClientRect JS ...
    // Change the last line:
    await showTouchIndicator(x: x, y: y, color: color)
}
```

**Step 3: Add a hex-to-RGB helper to HandlerContext**

```swift
/// Convert "#3B82F6" or "3B82F6" to "59,130,246" for rgba() use.
static func hexToRGB(_ hex: String) -> String {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard h.count == 6,
          let r = UInt8(h.prefix(2), radix: 16),
          let g = UInt8(h.dropFirst(2).prefix(2), radix: 16),
          let b = UInt8(h.dropFirst(4).prefix(2), radix: 16) else {
        return "59,130,246" // fallback to default blue
    }
    return "\(r),\(g),\(b)"
}
```

**Step 4: Copy identical changes to macOS HandlerContext.swift**

The macOS file has the same `showTouchIndicator` and `showTouchIndicatorForElement` methods. Apply the identical changes.

**Step 5: Verify build**

Run: `make lint-swift` from the project root.

**Step 6: Commit**

```
feat: add color parameter to touch indicator overlay
```

---

## Task 2: CommentaryHandler — iOS + macOS

**Files:**
- Create: `apps/ios/Kelpie/Handlers/CommentaryHandler.swift`
- Create: `apps/macos/Kelpie/Handlers/CommentaryHandler.swift`
- Modify: `apps/ios/Kelpie/Network/ServerState.swift` (line ~98, add registration)
- Modify: `apps/macos/Kelpie/Network/ServerState.swift` (equivalent line)

**Step 1: Create CommentaryHandler.swift (iOS)**

```swift
/// Handles show-commentary and hide-commentary endpoints.
struct CommentaryHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("show-commentary") { body in await showCommentary(body) }
        router.register("hide-commentary") { body in await hideCommentary(body) }
    }

    @MainActor
    private func showCommentary(_ body: [String: Any]) async -> [String: Any] {
        guard let text = body["text"] as? String else {
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

        let autoFade = durationMs > 0 ? """
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
            \(autoFade)
        })();
        """
        try? await context.evaluateJS(js)
        return successResponse(["text": text, "position": position, "durationMs": durationMs])
    }

    @MainActor
    private func hideCommentary(_ body: [String: Any]) async -> [String: Any] {
        let js = """
        (function() {
            var el = document.getElementById('__kelpie_commentary');
            if (el) {
                el.style.opacity = '0';
                setTimeout(function() { el.remove(); }, 300);
            }
        })();
        """
        try? await context.evaluateJS(js)
        return successResponse()
    }
}
```

**Step 2: Register in iOS ServerState.swift**

Add after the last handler registration (line ~99):

```swift
CommentaryHandler(context: ctx).register(on: router)
```

**Step 3: Copy to macOS**

Copy `CommentaryHandler.swift` to `apps/macos/Kelpie/Handlers/`. Add the same registration line to macOS `ServerState.swift`.

**Step 4: Verify build, commit**

```
feat: add show-commentary and hide-commentary endpoints
```

---

## Task 3: SwipeHandler — iOS + macOS

**Files:**
- Create: `apps/ios/Kelpie/Handlers/SwipeHandler.swift`
- Create: `apps/macos/Kelpie/Handlers/SwipeHandler.swift`
- Modify: `apps/ios/Kelpie/Network/ServerState.swift`
- Modify: `apps/macos/Kelpie/Network/ServerState.swift`

**Step 1: Create SwipeHandler.swift (iOS)**

```swift
/// Handles the swipe gesture endpoint — dispatches pointer events and shows a swipe trail overlay.
struct SwipeHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("swipe") { body in await swipe(body) }
    }

    @MainActor
    private func swipe(_ body: [String: Any]) async -> [String: Any] {
        guard let from = body["from"] as? [String: Double],
              let to = body["to"] as? [String: Double],
              let fx = from["x"], let fy = from["y"],
              let tx = to["x"], let ty = to["y"] else {
            return errorResponse(code: "MISSING_PARAM", message: "from: {x,y} and to: {x,y} are required")
        }
        let durationMs = body["durationMs"] as? Int ?? 400
        let steps = body["steps"] as? Int ?? 20
        let colorHex = body["color"] as? String ?? "#3B82F6"
        let rgb = HandlerContext.hexToRGB(colorHex)

        // Dispatch pointer events
        let stepDelay = steps > 0 ? durationMs / steps : 20
        for i in 0...steps {
            let t = steps > 0 ? Double(i) / Double(steps) : 1.0
            let cx = fx + (tx - fx) * t
            let cy = fy + (ty - fy) * t
            let eventType = i == 0 ? "pointerdown" : (i == steps ? "pointerup" : "pointermove")
            let js = """
            (function() {
                var el = document.elementFromPoint(\(cx), \(cy));
                if (!el) el = document.body;
                el.dispatchEvent(new PointerEvent('\(eventType)', {
                    clientX: \(cx), clientY: \(cy), bubbles: true, cancelable: true, pointerId: 1
                }));
            })()
            """
            _ = try? await context.evaluateJS(js)
            if i < steps {
                try? await Task.sleep(nanoseconds: UInt64(stepDelay) * 1_000_000)
            }
        }

        // Show swipe trail overlay
        let trailJS = """
        (function() {
            var fx=\(fx),fy=\(fy),tx=\(tx),ty=\(ty),dur=\(durationMs);
            var dot = document.createElement('div');
            dot.style.cssText = 'position:fixed;left:'+fx+'px;top:'+fy+'px;width:36px;height:36px;' +
                'margin-left:-18px;margin-top:-18px;border-radius:50%;' +
                'background:rgba(\(rgb),0.7);pointer-events:none;z-index:2147483647;' +
                'transition:left '+dur+'ms linear, top '+dur+'ms linear;';
            document.body.appendChild(dot);
            requestAnimationFrame(function() { dot.style.left = tx+'px'; dot.style.top = ty+'px'; });
            for (var i = 0; i < 6; i++) {
                (function(idx) {
                    var trail = document.createElement('div');
                    trail.style.cssText = 'position:fixed;left:'+fx+'px;top:'+fy+'px;width:12px;height:12px;' +
                        'margin-left:-6px;margin-top:-6px;border-radius:50%;' +
                        'background:rgba(\(rgb),'+(0.5 - idx*0.08)+');pointer-events:none;z-index:2147483647;' +
                        'transition:left '+dur+'ms linear, top '+dur+'ms linear;opacity:1;';
                    document.body.appendChild(trail);
                    setTimeout(function() { trail.style.left = tx+'px'; trail.style.top = ty+'px'; }, idx * 30);
                    setTimeout(function() { trail.remove(); }, dur + 400);
                })(i);
            }
            setTimeout(function() { dot.remove(); }, dur + 400);
        })();
        """
        try? await context.evaluateJS(trailJS)

        // Classify direction
        let dx = tx - fx, dy = ty - fy
        let direction: String
        if dy <= -100 && abs(dx) < 50 { direction = "up" }
        else if dy >= 100 && abs(dx) < 50 { direction = "down" }
        else if dx <= -100 && abs(dy) < 50 { direction = "left" }
        else if dx >= 100 && abs(dy) < 50 { direction = "right" }
        else { direction = "diagonal" }

        return successResponse([
            "from": ["x": fx, "y": fy],
            "to": ["x": tx, "y": ty],
            "durationMs": durationMs,
            "direction": direction
        ])
    }
}
```

**Step 2: Register in ServerState, copy to macOS, verify build, commit**

```
feat: add swipe gesture endpoint with trail overlay
```

---

## Task 4: HighlightHandler — iOS + macOS

**Files:**
- Create: `apps/ios/Kelpie/Handlers/HighlightHandler.swift`
- Create: `apps/macos/Kelpie/Handlers/HighlightHandler.swift`
- Modify: `apps/ios/Kelpie/Network/ServerState.swift`
- Modify: `apps/macos/Kelpie/Network/ServerState.swift`

**Step 1: Create HighlightHandler.swift (iOS)**

```swift
/// Handles highlight and hide-highlight endpoints — draws attention rings around elements.
struct HighlightHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("highlight") { body in await highlight(body) }
        router.register("hide-highlight") { body in await hideHighlight(body) }
    }

    @MainActor
    private func highlight(_ body: [String: Any]) async -> [String: Any] {
        guard let selector = body["selector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let color = body["color"] as? String ?? "#EF4444"
        let thickness = body["thickness"] as? Int ?? 2
        let padding = body["padding"] as? Int ?? 4
        let animation = body["animation"] as? String ?? "appear"
        let durationMs = body["durationMs"] as? Int ?? 2000

        let autoRemove = durationMs > 0 ? """
            setTimeout(function() {
                hl.style.opacity = '0';
                setTimeout(function() { hl.remove(); }, 300);
            }, \(durationMs));
        """ : ""

        if animation == "draw" {
            // SVG stroke-dashoffset animation
            let js = """
            (function() {
                var existing = document.getElementById('__kelpie_highlight');
                if (existing) existing.remove();
                var el = document.querySelector('\(JSEscape.string(selector))');
                if (!el) return null;
                var r = el.getBoundingClientRect();
                var pad = \(padding);
                var x = r.left - pad + window.scrollX;
                var y = r.top - pad + window.scrollY;
                var w = r.width + pad * 2;
                var h = r.height + pad * 2;
                var rx = 8;
                var perimeter = 2 * (w + h - 4 * rx) + 2 * Math.PI * rx;
                var ns = 'http://www.w3.org/2000/svg';
                var svg = document.createElementNS(ns, 'svg');
                svg.id = '__kelpie_highlight';
                svg.setAttribute('width', w);
                svg.setAttribute('height', h);
                svg.style.cssText = 'position:absolute;left:'+x+'px;top:'+y+'px;pointer-events:none;z-index:2147483647;overflow:visible;';
                var rect = document.createElementNS(ns, 'rect');
                rect.setAttribute('x', \(thickness)/2);
                rect.setAttribute('y', \(thickness)/2);
                rect.setAttribute('width', w - \(thickness));
                rect.setAttribute('height', h - \(thickness));
                rect.setAttribute('rx', rx);
                rect.setAttribute('fill', 'none');
                rect.setAttribute('stroke', '\(JSEscape.string(color))');
                rect.setAttribute('stroke-width', \(thickness));
                rect.style.strokeDasharray = perimeter;
                rect.style.strokeDashoffset = perimeter;
                rect.style.transition = 'stroke-dashoffset 600ms ease-out';
                svg.appendChild(rect);
                document.body.appendChild(svg);
                var hl = svg;
                requestAnimationFrame(function() { rect.style.strokeDashoffset = '0'; });
                \(autoRemove)
                return {x: x, y: y, width: w, height: h};
            })()
            """
            do {
                let result = try await context.evaluateJSReturningJSON(js)
                if result.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(selector)") }
                return successResponse(["selector": selector, "animation": animation, "rect": result])
            } catch {
                return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
            }
        } else {
            // "appear" — simple div border with opacity transition
            let js = """
            (function() {
                var existing = document.getElementById('__kelpie_highlight');
                if (existing) existing.remove();
                var el = document.querySelector('\(JSEscape.string(selector))');
                if (!el) return null;
                var r = el.getBoundingClientRect();
                var pad = \(padding);
                var x = r.left - pad + window.scrollX;
                var y = r.top - pad + window.scrollY;
                var w = r.width + pad * 2;
                var h = r.height + pad * 2;
                var hl = document.createElement('div');
                hl.id = '__kelpie_highlight';
                hl.style.cssText = 'position:absolute;left:'+x+'px;top:'+y+'px;width:'+w+'px;height:'+h+'px;' +
                    'border:\(thickness)px solid \(JSEscape.string(color));border-radius:8px;' +
                    'pointer-events:none;z-index:2147483647;' +
                    'transition:opacity 150ms ease-out;opacity:0;box-sizing:border-box;';
                document.body.appendChild(hl);
                requestAnimationFrame(function() { hl.style.opacity = '1'; });
                \(autoRemove)
                return {x: x, y: y, width: w, height: h};
            })()
            """
            do {
                let result = try await context.evaluateJSReturningJSON(js)
                if result.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(selector)") }
                return successResponse(["selector": selector, "animation": animation, "rect": result])
            } catch {
                return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func hideHighlight(_ body: [String: Any]) async -> [String: Any] {
        let js = """
        (function() {
            var el = document.getElementById('__kelpie_highlight');
            if (el) {
                el.style.opacity = '0';
                setTimeout(function() { el.remove(); }, 300);
            }
        })();
        """
        try? await context.evaluateJS(js)
        return successResponse()
    }
}
```

**Step 2: Register in ServerState, copy to macOS, verify build, commit**

```
feat: add highlight and hide-highlight endpoints
```

---

## Task 5: Add `mode` Parameter to `fill`

**Files:**
- Modify: `apps/ios/Kelpie/Handlers/InteractionHandler.swift` (lines 62-88)
- Modify: `apps/macos/Kelpie/Handlers/InteractionHandler.swift` (identical)

**Step 1: Modify the `fill` method**

Replace the existing `fill` method body. After the existing instant-fill JS block and its `do/catch`, add a mode check at the top:

```swift
@MainActor
private func fill(_ body: [String: Any]) async -> [String: Any] {
    guard let selector = body["selector"] as? String, let value = body["value"] as? String else {
        return errorResponse(code: "MISSING_PARAM", message: "selector and value are required")
    }
    let mode = body["mode"] as? String ?? "instant"

    if mode == "typing" {
        // Focus the element first
        let focusJS = """
        (function() {
            var el = document.querySelector('\(JSEscape.string(selector))');
            if (!el) return null;
            el.focus();
            var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set || Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')?.set;
            if (nativeSetter) nativeSetter.call(el, '');
            else el.value = '';
            el.dispatchEvent(new Event('input', {bubbles: true}));
            return {found: true};
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(focusJS)
            if result.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(selector)") }
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
        // Type character by character (same as typeText)
        let delay = body["delay"] as? Int ?? 50
        for char in value {
            let escapedChar = JSEscape.string(String(char))
            let charJS = """
            (function() {
                var el = document.activeElement;
                if (!el) return;
                el.dispatchEvent(new KeyboardEvent('keydown', {key: '\(escapedChar)', bubbles: true}));
                el.dispatchEvent(new KeyboardEvent('keypress', {key: '\(escapedChar)', bubbles: true}));
                var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
                if (nativeSetter) nativeSetter.call(el, el.value + '\(escapedChar)');
                else el.value += '\(escapedChar)';
                el.dispatchEvent(new Event('input', {bubbles: true}));
                el.dispatchEvent(new KeyboardEvent('keyup', {key: '\(escapedChar)', bubbles: true}));
            })()
            """
            _ = try? await context.evaluateJS(charJS)
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
        }
        await context.showTouchIndicatorForElement(selector)
        return successResponse(["selector": selector, "value": value, "mode": "typing"])
    }

    // Instant mode (existing behavior)
    let js = """
    (function() {
        var el = document.querySelector('\(JSEscape.string(selector))');
        if (!el) return null;
        el.focus();
        var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set || Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')?.set;
        if (nativeSetter) nativeSetter.call(el, '\(JSEscape.string(value))');
        else el.value = '\(JSEscape.string(value))';
        el.dispatchEvent(new Event('input', {bubbles: true}));
        el.dispatchEvent(new Event('change', {bubbles: true}));
        return {selector: '\(JSEscape.string(selector))', value: '\(JSEscape.string(value))'};
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
```

**Step 2: Copy identical change to macOS InteractionHandler.swift**

**Step 3: Verify build, commit**

```
feat: add typing mode to fill endpoint with configurable delay
```

---

## Task 6: ScriptHandler — iOS + macOS

**Files:**
- Create: `apps/ios/Kelpie/Handlers/ScriptHandler.swift`
- Create: `apps/macos/Kelpie/Handlers/ScriptHandler.swift`
- Modify: `apps/ios/Kelpie/Network/ServerState.swift`
- Modify: `apps/macos/Kelpie/Network/ServerState.swift`

**Depends on:** Tasks 1-5

This is the largest handler. It orchestrates script playback by parsing the action array and delegating to existing handlers/HandlerContext methods.

**Step 1: Create ScriptHandler.swift (iOS)**

The handler needs to:
- Register `play-script`, `abort-script`, `get-script-status`
- Maintain playback state (current action index, start time, abort flag)
- Iterate actions, dispatch each to the appropriate handler method
- Return accumulated results when done

The full implementation is too long for inline code. Key structure:

```swift
/// Orchestrates scripted video recording playback.
struct ScriptHandler {
    let context: HandlerContext
    let interactionHandler: InteractionHandler
    let scrollHandler: ScrollHandler
    let navigationHandler: NavigationHandler
    let swipeHandler: SwipeHandler
    let highlightHandler: HighlightHandler
    let commentaryHandler: CommentaryHandler
    let screenshotHandler: ScreenshotHandler
    let evaluateHandler: EvaluateHandler
    let deviceHandler: DeviceHandler

    // Shared mutable state for abort/status (class wrapper needed since struct)
    let state: ScriptPlaybackState

    func register(on router: Router) {
        router.register("play-script") { body in await playScript(body) }
        router.register("abort-script") { body in await abortScript(body) }
        router.register("get-script-status") { body in await getScriptStatus(body) }
    }
}
```

`ScriptPlaybackState` is a `@MainActor final class` with:
- `var isPlaying = false`
- `var currentActionIndex = 0`
- `var totalActions = 0`
- `var startTime: Date?`
- `var shouldAbort = false`
- `var screenshots: [[String: Any]] = []`
- `var errors: [[String: Any]] = []`

The `playScript` method:
1. Parses `body["actions"]` as `[[String: Any]]`
2. Sets `state.isPlaying = true`
3. Loops through actions, calling `executeAction(_ action:)` for each
4. Inserts `defaultWaitBetweenActions` between actions (unless next is wait/sync)
5. Checks `state.shouldAbort` between actions
6. Sets `state.isPlaying = false` on completion
7. Returns the result summary

The `executeAction` method is a switch on `action["action"] as? String`:
- `"navigate"` → call existing NavigationHandler
- `"click"`, `"tap"`, `"fill"`, `"type"`, `"check"`, `"uncheck"`, `"select-option"` → call InteractionHandler
- `"scroll"`, `"scroll2"`, etc. → call ScrollHandler
- `"swipe"` → call SwipeHandler
- `"highlight"`, `"hide-highlight"` → call HighlightHandler
- `"commentary"`, `"hide-commentary"` → call CommentaryHandler
- `"screenshot"` → call ScreenshotHandler, store result in `state.screenshots`
- `"evaluate"` → call EvaluateHandler
- `"wait"` → `Task.sleep`
- `"wait-for-element"`, `"wait-for-navigation"` → delegate to existing wait handlers

**Important:** Since handlers are structs, the ScriptHandler needs references to the same handler instances registered on the Router. Pass them in from ServerState during registration.

**Step 2: Wire in ServerState.swift**

The ScriptHandler needs references to the other handlers. Refactor the registration slightly:

```swift
let interactionHandler = InteractionHandler(context: ctx)
interactionHandler.register(on: router)
// ... same for all handlers ...
let scriptHandler = ScriptHandler(
    context: ctx,
    interactionHandler: interactionHandler,
    scrollHandler: scrollHandler,
    // ... etc ...
    state: ScriptPlaybackState()
)
scriptHandler.register(on: router)
```

**Step 3: Copy to macOS, verify build, commit**

```
feat: add play-script, abort-script, get-script-status endpoints
```

---

## Task 7: Recording Mode Manager — iOS + macOS

**Files:**
- Create: `apps/ios/Kelpie/Recording/RecordingModeManager.swift`
- Create: `apps/macos/Kelpie/Recording/RecordingModeManager.swift`
- Modify: `apps/ios/Kelpie/Network/Router.swift` (add recording gate)
- Modify: `apps/macos/Kelpie/Network/Router.swift`

**Can run in parallel with Task 6.**

This task adds the UI lockdown during recording. The approach:

1. `RecordingModeManager` is an `ObservableObject` with `@Published var isRecording = false`
2. Router checks `isRecording` before dispatching — if true, only `abort-script` and `get-script-status` pass through
3. iOS: hides URL bar, toolbar, status bar insets via SwiftUI state
4. macOS: enters fullscreen, hides URL bar / tab strip / toolbar
5. Stop button appears (NSButton on macOS, UIButton on iOS)

**This is platform-specific and will diverge between iOS and macOS.** The detailed implementation depends on the current UI structure of each app, which needs to be explored at implementation time. The key contract:

```swift
@MainActor
final class RecordingModeManager: ObservableObject {
    @Published var isRecording = false

    func enterRecordingMode() { isRecording = true; /* hide chrome */ }
    func exitRecordingMode() { isRecording = false; /* restore chrome */ }
}
```

**Router gate (add to Router.handle):**

```swift
func handle(method: String, body: [String: Any]) async -> (Int, [String: Any]) {
    // Recording mode gate
    if handlerContext?.recordingModeManager?.isRecording == true {
        let allowed = ["abort-script", "get-script-status"]
        if !allowed.contains(method) {
            return (409, errorResponse(code: "RECORDING_IN_PROGRESS",
                message: "Script is playing. Call abort-script to stop."))
        }
    }
    // ... existing dispatch ...
}
```

**Step: Implement, verify build, commit**

```
feat: add recording mode with UI lockdown and stop button
```

---

## Task 8: CLI Commands

**Files:**
- Create: `packages/cli/src/commands/script.ts`
- Modify: `packages/cli/src/commands/index.ts` (add registration)

**Depends on:** Tasks 1-7

**Step 1: Create script.ts**

```typescript
import type { Command } from "commander";
import { readFileSync } from "fs";
import { deviceCommand } from "./helpers.js";

export function registerScript(program: Command): void {
  program
    .command("script <file>")
    .description("Play a scripted video recording from a JSON file")
    .action(async (file: string) => {
      const content = readFileSync(file, "utf-8");
      const script = JSON.parse(content);
      await deviceCommand(program, "play-script", script);
    });

  program
    .command("swipe")
    .description("Perform a swipe gesture")
    .requiredOption("--from-x <n>", "Start X coordinate", Number)
    .requiredOption("--from-y <n>", "Start Y coordinate", Number)
    .requiredOption("--to-x <n>", "End X coordinate", Number)
    .requiredOption("--to-y <n>", "End Y coordinate", Number)
    .option("--duration <ms>", "Swipe duration in ms", Number)
    .option("--steps <n>", "Interpolation steps", Number)
    .action(async (opts) => {
      const body: Record<string, unknown> = {
        from: { x: opts.fromX, y: opts.fromY },
        to: { x: opts.toX, y: opts.toY },
      };
      if (opts.duration) body.durationMs = opts.duration;
      if (opts.steps) body.steps = opts.steps;
      await deviceCommand(program, "swipe", body);
    });

  program
    .command("commentary <text>")
    .description("Show a commentary overlay on the device")
    .option("--duration <ms>", "Display duration in ms", Number)
    .option("--position <pos>", "Position: top, center, bottom")
    .action(async (text: string, opts) => {
      const body: Record<string, unknown> = { text };
      if (opts.duration) body.durationMs = opts.duration;
      if (opts.position) body.position = opts.position;
      await deviceCommand(program, "show-commentary", body);
    });

  program
    .command("highlight <selector>")
    .description("Highlight an element on the device")
    .option("--color <color>", "Highlight color (hex)")
    .option("--thickness <n>", "Border thickness in px", Number)
    .option("--animation <type>", "Animation: appear or draw")
    .option("--duration <ms>", "Display duration in ms", Number)
    .action(async (selector: string, opts) => {
      const body: Record<string, unknown> = { selector };
      if (opts.color) body.color = opts.color;
      if (opts.thickness) body.thickness = opts.thickness;
      if (opts.animation) body.animation = opts.animation;
      if (opts.duration) body.durationMs = opts.duration;
      await deviceCommand(program, "highlight", body);
    });
}
```

**Step 2: Register in index.ts**

Add `registerScript(program)` to the command registration list.

**Step 3: Verify: `pnpm lint && pnpm build`**

**Step 4: Commit**

```
feat(cli): add script, swipe, commentary, highlight commands
```

---

## Task 9: MCP Tool Registration

**Files:**
- Modify: `packages/cli/src/mcp/tools.ts` (add tool definitions to `browserTools` array)

**Depends on:** Task 8

**Step 1: Add new tools to the `browserTools` array**

Add these entries to the `browserTools` array in `tools.ts`:

```typescript
// Swipe
{ name: "kelpie_swipe", description: "Perform a swipe gesture between two points. Shows a visual swipe trail overlay.", method: "swipe", schema: {
  device,
  from: z.object({ x: z.number(), y: z.number() }).describe("Start point"),
  to: z.object({ x: z.number(), y: z.number() }).describe("End point"),
  durationMs: z.number().optional().describe("Swipe duration in ms (default 400)"),
  steps: z.number().optional().describe("Interpolation steps (default 20)"),
  color: z.string().optional().describe("Overlay color as hex (default #3B82F6)"),
}, bodyFromArgs: passthrough },

// Commentary
{ name: "kelpie_show_commentary", description: "Show a text commentary overlay on the viewport", method: "show-commentary", schema: {
  device,
  text: z.string().describe("Commentary text to display"),
  durationMs: z.number().optional().describe("Display duration in ms (default 3000, 0 = persistent)"),
  position: z.enum(["top", "center", "bottom"]).optional().describe("Overlay position (default bottom)"),
}, bodyFromArgs: passthrough },
{ name: "kelpie_hide_commentary", description: "Hide the active commentary overlay", method: "hide-commentary", schema: { device }, bodyFromArgs: passthrough },

// Highlight
{ name: "kelpie_highlight", description: "Draw a highlight ring around a DOM element to call attention to it", method: "highlight", schema: {
  device,
  selector,
  color: z.string().optional().describe("Ring color as CSS color (default #EF4444)"),
  thickness: z.number().optional().describe("Border width in px (default 2)"),
  padding: z.number().optional().describe("Space between element and ring in px (default 4)"),
  animation: z.enum(["appear", "draw"]).optional().describe("appear = instant, draw = animated stroke (default appear)"),
  durationMs: z.number().optional().describe("Display duration in ms (default 2000, 0 = persistent)"),
}, bodyFromArgs: passthrough },
{ name: "kelpie_hide_highlight", description: "Hide the active highlight overlay", method: "hide-highlight", schema: { device }, bodyFromArgs: passthrough },

// Script playback
{ name: "kelpie_play_script", description: "Play a scripted sequence of browser actions with visual overlays. The device enters recording mode (all UI hidden except a stop button). Actions execute sequentially with precise timing. Use this to create demo walkthroughs.", method: "play-script", schema: {
  device,
  actions: z.array(z.record(z.unknown())).describe("Ordered array of action objects. Each has an 'action' field (navigate, click, tap, fill, type, scroll, swipe, commentary, highlight, wait, etc.) plus action-specific parameters matching the individual endpoint schemas."),
  overlayColor: z.string().optional().describe("Default color for touch indicators and swipe trails (hex, default #3B82F6)"),
  defaultWaitBetweenActions: z.number().optional().describe("Implicit pause in ms between actions (default 0)"),
  continueOnError: z.boolean().optional().describe("If true, skip failed actions instead of stopping (default false)"),
}, bodyFromArgs: passthrough },
{ name: "kelpie_abort_script", description: "Stop a currently playing script and exit recording mode", method: "abort-script", schema: { device }, bodyFromArgs: passthrough },
{ name: "kelpie_get_script_status", description: "Get the current script playback status", method: "get-script-status", schema: { device }, bodyFromArgs: passthrough },
```

**Step 2: Verify: `pnpm lint && pnpm build`**

**Step 3: Commit**

```
feat(cli): register MCP tools for script, swipe, commentary, highlight
```

---

## Task 10: Documentation Updates

**Files:**
- Modify: `docs/api/core.md`
- Modify: `docs/api/README.md`
- Modify: `docs/functionality.md`
- Modify: `docs/cli.md`

**Depends on:** Task 9

**Step 1: Add new endpoints to core.md**

Add sections for: `swipe`, `show-commentary`, `hide-commentary`, `highlight`, `hide-highlight`, `play-script`, `abort-script`, `get-script-status`. Follow the existing format (endpoint, JSON request/response examples).

**Step 2: Add MCP tool names to README.md table**

Add rows for all 8 new tools to the MCP Tool Names table.

**Step 3: Add `RECORDING_IN_PROGRESS` to error codes table in README.md**

```
| `RECORDING_IN_PROGRESS` | 409 | Script is playing; only abort-script and get-script-status are allowed |
```

**Step 4: Update functionality.md**

Add a "Scripted Video Recording" feature entry.

**Step 5: Update cli.md**

Add `script`, `swipe`, `commentary`, `highlight` commands.

**Step 6: Commit**

```
docs: add scripted video recording endpoints, MCP tools, and CLI commands
```

---

## Execution Notes

- **Tasks 1-5 are independent** — dispatch as parallel sub-agents
- **Task 6 (ScriptHandler)** is the most complex single file — it needs all handler references. May need to be split into two commits: one for the state class, one for the handler
- **Task 7 (Recording Mode)** requires exploring the current iOS/macOS UI structure — the sub-agent will need to read the main ContentView/AppDelegate to understand how to hide chrome
- **iOS and macOS handler files are identical** except where noted (HandlerContext differences). Copy iOS → macOS for all new handlers
- **The 500-line file limit** (from AGENTS.md) applies. ScriptHandler may approach this; if so, extract the action dispatch switch into a separate `ScriptActionDispatcher` struct
