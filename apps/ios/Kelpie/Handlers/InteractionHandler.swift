import WebKit

private struct TapExecution {
    let requestedX: Double
    let requestedY: Double
    let appliedX: Double
    let appliedY: Double
    let offsetX: Double
    let offsetY: Double

    var responsePayload: [String: Any] {
        [
            "x": requestedX,
            "y": requestedY,
            "appliedX": appliedX,
            "appliedY": appliedY,
            "offsetX": offsetX,
            "offsetY": offsetY
        ]
    }
}

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
        let color = overlayColor(from: body)
        do {
            let result = try await context.evaluateJSReturningJSON(selectorActivationScript(selector))
            let diagnostics = result["diagnostics"] as? [String: Any]
            if result.isEmpty || result["error"] as? String == "not_found" {
                return errorResponse(
                    code: "ELEMENT_NOT_FOUND",
                    message: "Element not found: \(selector)",
                    diagnostics: diagnostics
                )
            }
            if result["error"] as? String == "not_visible" {
                return errorResponse(
                    code: "ELEMENT_NOT_VISIBLE",
                    message: "Element is not visible or is obscured: \(selector)",
                    diagnostics: diagnostics
                )
            }
            if let center = result["center"] as? [String: Any],
               let x = double(center["x"]), let y = double(center["y"]) {
                await context.showTouchIndicator(x: x, y: y, color: color)
            } else {
                await context.showTouchIndicatorForElement(selector, color: color)
            }
            return successResponse(["element": result])
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func tap(_ body: [String: Any]) async -> [String: Any] {
        guard var requestedX = double(body["x"]), var requestedY = double(body["y"]) else {
            return errorResponse(code: "MISSING_PARAM", message: "x and y are required")
        }
        let coordinateSpace = (body["coordinateSpace"] as? String ?? "viewport").lowercased()
        if coordinateSpace == "screenshot" {
            do {
                let metrics = try await context.screenshotViewportMetrics()
                let dpr = max(metrics.devicePixelRatio, 1)
                requestedX /= dpr
                requestedY /= dpr
            } catch {
                return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
            }
        }
        let execution: TapExecution
        do {
            execution = try await calibratedTapExecution(
                requestedX: requestedX,
                requestedY: requestedY,
                calibration: TapCalibrationStore.current()
            )
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
        await context.showTouchIndicator(
            x: execution.appliedX,
            y: execution.appliedY,
            color: overlayColor(from: body)
        )
        do {
            let diagnostics = try await context.evaluateJSReturningJSON(tapScript(execution: execution))
            return successResponse(execution.responsePayload.merging(["diagnostics": diagnostics]) { _, new in new })
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func fill(_ body: [String: Any]) async -> [String: Any] {
        guard let selector = body["selector"] as? String, let value = body["value"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector and value are required")
        }
        let color = overlayColor(from: body)
        let mode = (body["mode"] as? String ?? "instant").lowercased()
        let delay = body["delay"] as? Int ?? 50

        if mode == "typing" {
            let focusJS = "document.querySelector('\(JSEscape.string(selector))')?.focus()"
            _ = try? await context.evaluateJS(focusJS)
            do {
                let focusResult = try await context.evaluateJSReturningJSON(fillElementScript(selector: selector, value: ""))
                let diagnostics = focusResult["diagnostics"] as? [String: Any]
                if focusResult.isEmpty || focusResult["error"] as? String == "not_found" {
                    return errorResponse(
                        code: "ELEMENT_NOT_FOUND",
                        message: "Element not found: \(selector)",
                        diagnostics: diagnostics
                    )
                }
                if focusResult["error"] as? String == "not_editable" {
                    return errorResponse(
                        code: "INVALID_PARAMS",
                        message: "Element is not an editable form control: \(selector)",
                        diagnostics: diagnostics
                    )
                }
                return await typeText([
                    "selector": selector,
                    "text": value,
                    "delay": delay,
                    "color": body["color"] as Any
                ].compactMapValues { $0 })
            } catch {
                return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
            }
        }

        do {
            let result = try await context.evaluateJSReturningJSON(fillElementScript(selector: selector, value: value))
            let diagnostics = result["diagnostics"] as? [String: Any]
            if result.isEmpty || result["error"] as? String == "not_found" {
                return errorResponse(
                    code: "ELEMENT_NOT_FOUND",
                    message: "Element not found: \(selector)",
                    diagnostics: diagnostics
                )
            }
            if result["error"] as? String == "not_editable" {
                return errorResponse(
                    code: "INVALID_PARAMS",
                    message: "Element is not an editable form control: \(selector)",
                    diagnostics: diagnostics
                )
            }
            await context.showTouchIndicatorForElement(selector, color: color)
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
        let color = overlayColor(from: body)
        if let selector = body["selector"] as? String {
            let focusJS = "document.querySelector('\(JSEscape.string(selector))')?.focus()"
            _ = try? await context.evaluateJS(focusJS)
            await context.showTouchIndicatorForElement(selector, color: color)
        }
        let delay = body["delay"] as? Int ?? 50
        for char in text {
            if context.scriptPlaybackState?.isAbortRequested() == true { break }
            let escapedChar = JSEscape.string(String(char))
            let charJS = """
            (function() {
                \(formControlMutationScript())
                var el = document.activeElement;
                if (!el) return;
                el.dispatchEvent(new KeyboardEvent('keydown', {key: '\(escapedChar)', bubbles: true}));
                el.dispatchEvent(new KeyboardEvent('keypress', {key: '\(escapedChar)', bubbles: true}));
                kelpieWriteFormControlValue(el, kelpieReadFormControlValue(el) + '\(escapedChar)');
                kelpieDispatchFormControlInput(el);
                el.dispatchEvent(new KeyboardEvent('keyup', {key: '\(escapedChar)', bubbles: true}));
            })()
            """
            _ = try? await context.evaluateJS(charJS)
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
        }
        let finalizeJS = """
        (function() {
            \(formControlMutationScript())
            var el = document.activeElement;
            if (!el) return;
            kelpieDispatchFormControlChange(el);
        })()
        """
        _ = try? await context.evaluateJS(finalizeJS)
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
            await context.showTouchIndicatorForElement(selector, color: overlayColor(from: body))
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
            await context.showTouchIndicatorForElement(selector, color: overlayColor(from: body))
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    private func overlayColor(from body: [String: Any]) -> String {
        HandlerContext.hexToRGB(body["color"] as? String ?? "#3B82F6")
    }

    private func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    @MainActor
    private func calibratedTapExecution(
        requestedX: Double,
        requestedY: Double,
        calibration: TapCalibration
    ) async throws -> TapExecution {
        let viewport = try await viewportSize()
        let appliedX = clamp(requestedX + calibration.offsetX, min: 0, max: max(viewport.width - 1, 0))
        let appliedY = clamp(requestedY + calibration.offsetY, min: 0, max: max(viewport.height - 1, 0))
        return TapExecution(
            requestedX: requestedX,
            requestedY: requestedY,
            appliedX: appliedX,
            appliedY: appliedY,
            offsetX: calibration.offsetX,
            offsetY: calibration.offsetY
        )
    }

    @MainActor
    private func viewportSize() async throws -> (width: Double, height: Double) {
        let result = try await context.evaluateJSReturningJSON("""
        (function() {
            return {
                width: Math.max(window.innerWidth || 0, 1),
                height: Math.max(window.innerHeight || 0, 1)
            };
        })()
        """)
        let width = double(result["width"]) ?? 1
        let height = double(result["height"]) ?? 1
        return (width, height)
    }

    private func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        guard lower <= upper else { return lower }
        return Swift.min(Swift.max(value, lower), upper)
    }

    private func tapScript(execution: TapExecution) -> String {
        """
        (function() {
            \(interactionHelpersScript())
            var requestedX = \(execution.requestedX);
            var requestedY = \(execution.requestedY);
            var appliedX = \(execution.appliedX);
            var appliedY = \(execution.appliedY);
            var offsetX = \(execution.offsetX);
            var offsetY = \(execution.offsetY);
            var hook = window.__kelpieTapCalibration;
            if (hook && typeof hook.onAutomationTap === 'function') {
                try {
                    hook.onAutomationTap({
                        requestedX: requestedX,
                        requestedY: requestedY,
                        appliedX: appliedX,
                        appliedY: appliedY,
                        offsetX: offsetX,
                        offsetY: offsetY
                    });
                } catch (error) {}
            }
            var eventTarget = document.elementFromPoint(appliedX, appliedY) || document.body || document.documentElement;
            if (!eventTarget) {
                return kelpieTapDiagnostics(null, requestedX, requestedY, appliedX, appliedY, offsetX, offsetY);
            }
            if (typeof eventTarget.focus === 'function') {
                try { eventTarget.focus({preventScroll: true}); } catch (error) { try { eventTarget.focus(); } catch (focusError) {} }
            }
            function dispatchMouse(type, button, buttons) {
                eventTarget.dispatchEvent(new MouseEvent(type, {
                    bubbles: true,
                    cancelable: true,
                    composed: true,
                    clientX: appliedX,
                    clientY: appliedY,
                    screenX: appliedX,
                    screenY: appliedY,
                    detail: type === 'click' ? 1 : 0,
                    button: button,
                    buttons: buttons
                }));
            }
            function dispatchPointer(type, button, buttons) {
                if (typeof window.PointerEvent !== 'function') {
                    return;
                }
                eventTarget.dispatchEvent(new PointerEvent(type, {
                    bubbles: true,
                    cancelable: true,
                    composed: true,
                    clientX: appliedX,
                    clientY: appliedY,
                    screenX: appliedX,
                    screenY: appliedY,
                    pointerId: 1,
                    pointerType: 'touch',
                    isPrimary: true,
                    button: button,
                    buttons: buttons
                }));
            }
            dispatchPointer('pointerdown', 0, 1);
            dispatchMouse('mousedown', 0, 1);
            dispatchPointer('pointerup', 0, 0);
            dispatchMouse('mouseup', 0, 0);
            if (typeof eventTarget.click === 'function') {
                eventTarget.click();
            } else {
                dispatchMouse('click', 0, 0);
            }
            return kelpieTapDiagnostics(eventTarget, requestedX, requestedY, appliedX, appliedY, offsetX, offsetY);
        })()
        """
    }
}
