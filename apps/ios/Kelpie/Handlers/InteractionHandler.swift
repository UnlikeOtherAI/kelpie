import WebKit

/// Handles click, tap, fill, type, selectOption, check, uncheck.
struct InteractionHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("click") { body in await click(body) }
        router.register("tap") { body in await tap(body) }
        router.register("fill") { body in await fill(body) }
        router.register("type") { body in await typeText(body) }
        router.register("select-option") { body in await selectOption(body) }
        router.register("check") { body in await setChecked(body, checked: true) }
        router.register("uncheck") { body in await setChecked(body, checked: false) }
    }

    @MainActor
    private func click(_ body: [String: Any]) async -> [String: Any] {
        guard let selector = body["selector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let js = """
        (function() {
            var el = document.querySelector('\(JSEscape.string(selector))');
            if (!el) return null;
            el.scrollIntoView({block: 'center'});
            el.click();
            return {tag: el.tagName.toLowerCase(), text: (el.textContent || '').trim().substring(0, 100)};
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            if result.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(selector)") }
            await context.showTouchIndicatorForElement(selector)
            return successResponse(["element": result])
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func tap(_ body: [String: Any]) async -> [String: Any] {
        guard let x = body["x"] as? Double, let y = body["y"] as? Double else {
            return errorResponse(code: "MISSING_PARAM", message: "x and y are required")
        }
        await context.showTouchIndicator(x: x, y: y)
        let js = """
        (function() {
            var el = document.elementFromPoint(\(x), \(y));
            if (el) el.click();
            return {x: \(x), y: \(y)};
        })()
        """
        do {
            _ = try await context.evaluateJS(js)
            return successResponse(["x": x, "y": y])
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func fill(_ body: [String: Any]) async -> [String: Any] {
        guard let selector = body["selector"] as? String, let value = body["value"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector and value are required")
        }
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

    @MainActor
    private func typeText(_ body: [String: Any]) async -> [String: Any] {
        guard let text = body["text"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "text is required")
        }
        if let selector = body["selector"] as? String {
            let focusJS = "document.querySelector('\(JSEscape.string(selector))')?.focus()"
            _ = try? await context.evaluateJS(focusJS)
        }
        let delay = body["delay"] as? Int ?? 50
        for char in text {
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
        return successResponse(["typed": text])
    }

    @MainActor
    private func selectOption(_ body: [String: Any]) async -> [String: Any] {
        guard let selector = body["selector"] as? String, let value = body["value"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector and value are required")
        }
        let js = """
        (function() {
            var el = document.querySelector('\(JSEscape.string(selector))');
            if (!el) return null;
            el.value = '\(JSEscape.string(value))';
            el.dispatchEvent(new Event('change', {bubbles: true}));
            var opt = el.options?.[el.selectedIndex];
            return {selected: {value: el.value, text: opt ? opt.text : el.value}};
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            if result.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(selector)") }
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func setChecked(_ body: [String: Any], checked: Bool) async -> [String: Any] {
        guard let selector = body["selector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let js = """
        (function() {
            var el = document.querySelector('\(JSEscape.string(selector))');
            if (!el) return null;
            el.checked = \(checked);
            el.dispatchEvent(new Event('change', {bubbles: true}));
            return {checked: el.checked};
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            if result.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Element not found: \(selector)") }
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }
}
