package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse

class InteractionHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("click") { click(it) }
        router.register("tap") { tap(it) }
        router.register("fill") { fill(it) }
        router.register("type") { type(it) }
        router.register("select-option") { selectOption(it) }
        router.register("check") { check(it) }
        router.register("uncheck") { uncheck(it) }
    }

    private suspend fun click(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        return try {
            val result = ctx.evaluateJSReturningJSON(selectorActivationScript(selector))
            val diagnostics = result["diagnostics"] as? Map<String, Any?>
            when (result["error"]) {
                "not_found" -> {
                    errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector", diagnostics)
                }

                "not_visible" -> {
                    errorResponse("ELEMENT_NOT_VISIBLE", "Element is not visible or is obscured: $selector", diagnostics)
                }

                null -> {
                    val center = result["center"] as? Map<*, *>
                    val x = (center?.get("x") as? Number)?.toDouble()
                    val y = (center?.get("y") as? Number)?.toDouble()
                    if (x != null && y != null) {
                        ctx.showTouchIndicator(x, y, ctx.overlayColor(body))
                    } else {
                        ctx.showTouchIndicatorForElement(selector, ctx.overlayColor(body))
                    }
                    successResponse(mapOf("element" to result))
                }

                else -> {
                    errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector")
                }
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun tap(body: Map<String, Any?>): Map<String, Any?> {
        var requestedX = (body["x"] as? Number)?.toDouble() ?: return errorResponse("MISSING_PARAM", "x and y are required")
        var requestedY = (body["y"] as? Number)?.toDouble() ?: return errorResponse("MISSING_PARAM", "x and y are required")
        val coordinateSpace = (body["coordinateSpace"] as? String ?: "viewport").lowercase()
        if (coordinateSpace == "screenshot") {
            try {
                val metrics = ctx.viewportMetrics()
                val dpr = maxOf(metrics.devicePixelRatio, 1.0)
                requestedX /= dpr
                requestedY /= dpr
            } catch (e: Exception) {
                return errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
            }
        }
        val execution =
            try {
                calibratedTapExecution(requestedX, requestedY, TapCalibrationStore.current())
            } catch (e: Exception) {
                return errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
            }
        ctx.showTouchIndicator(execution.appliedX, execution.appliedY, ctx.overlayColor(body))
        return try {
            val diagnostics = ctx.evaluateJSReturningJSON(tapScript(execution))
            successResponse(
                mapOf(
                    "x" to execution.requestedX,
                    "y" to execution.requestedY,
                    "appliedX" to execution.appliedX,
                    "appliedY" to execution.appliedY,
                    "offsetX" to execution.offsetX,
                    "offsetY" to execution.offsetY,
                    "diagnostics" to diagnostics,
                ),
            )
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun fill(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val value = body["value"] as? String ?: return errorResponse("MISSING_PARAM", "value is required")
        val mode = (body["mode"] as? String ?: "instant").lowercase()
        val delay = (body["delay"] as? Int) ?: 50
        if (mode == "typing") {
            return try {
                val focusResult = ctx.evaluateJSReturningJSON(fillElementScript(selector, ""))
                val diagnostics = focusResult["diagnostics"] as? Map<String, Any?>
                when (focusResult["error"]) {
                    "not_found" -> errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector", diagnostics)
                    "not_editable" -> errorResponse("INVALID_PARAMS", "Element is not an editable form control: $selector", diagnostics)
                    null ->
                        type(
                            mapOf(
                                "selector" to selector,
                                "text" to value,
                                "delay" to delay,
                                "color" to body["color"],
                            ),
                        )
                    else -> errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector", diagnostics)
                }
            } catch (e: Exception) {
                errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
            }
        }
        return try {
            val result = ctx.evaluateJSReturningJSON(fillElementScript(selector, value))
            val diagnostics = result["diagnostics"] as? Map<String, Any?>
            when (result["error"]) {
                "not_found" -> errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector", diagnostics)
                "not_editable" -> errorResponse("INVALID_PARAMS", "Element is not an editable form control: $selector", diagnostics)
                null -> {
                    ctx.showTouchIndicatorForElement(selector, ctx.overlayColor(body))
                    successResponse(mapOf("element" to result))
                }

                else -> {
                    errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector", diagnostics)
                }
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun type(body: Map<String, Any?>): Map<String, Any?> {
        val text = body["text"] as? String ?: return errorResponse("MISSING_PARAM", "text is required")
        val selector = body["selector"] as? String
        if (selector != null) {
            val focusJs = "document.querySelector('${JSEscape.string(selector)}')?.focus()"
            runCatching { ctx.evaluateJS(focusJs) }
            ctx.showTouchIndicatorForElement(selector, ctx.overlayColor(body))
        }
        val delayMs = (body["delay"] as? Int) ?: 50
        return try {
            for (char in text) {
                if (ctx.scriptPlaybackState?.isAbortRequested() == true) break
                val escapedChar = JSEscape.string(char.toString())
                val charJs =
                    """
                    (function() {
                        ${formControlMutationScript()}
                        var el = document.activeElement;
                        if (!el) return;
                        el.dispatchEvent(new KeyboardEvent('keydown', {key: '$escapedChar', bubbles: true}));
                        el.dispatchEvent(new KeyboardEvent('keypress', {key: '$escapedChar', bubbles: true}));
                        kelpieWriteFormControlValue(el, kelpieReadFormControlValue(el) + '$escapedChar');
                        kelpieDispatchFormControlInput(el);
                        el.dispatchEvent(new KeyboardEvent('keyup', {key: '$escapedChar', bubbles: true}));
                    })()
                    """.trimIndent()
                ctx.evaluateJS(charJs)
                kotlinx.coroutines.delay(delayMs.toLong())
            }
            ctx.evaluateJS(
                """
                (function() {
                    ${formControlMutationScript()}
                    var el = document.activeElement;
                    if (!el) return;
                    kelpieDispatchFormControlChange(el);
                })()
                """.trimIndent(),
            )
            successResponse(mapOf("typed" to text))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun selectOption(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val value = body["value"] as? String ?: return errorResponse("MISSING_PARAM", "value is required")
        val js =
            "(function(){var el=document.querySelector('${JSEscape.string(selector)}');" +
                "if(!el)return null;el.value='${JSEscape.string(value)}';" +
                "el.dispatchEvent(new Event('change',{bubbles:true}));" +
                "return{tag:'select',value:el.value};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) {
                errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector")
            } else {
                ctx.showTouchIndicatorForElement(selector, ctx.overlayColor(body))
                successResponse(mapOf("element" to result))
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun check(body: Map<String, Any?>): Map<String, Any?> = setChecked(body, true)

    private suspend fun uncheck(body: Map<String, Any?>): Map<String, Any?> = setChecked(body, false)

    private suspend fun setChecked(
        body: Map<String, Any?>,
        checked: Boolean,
    ): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val js =
            "(function(){var el=document.querySelector('${JSEscape.string(selector)}');" +
                "if(!el)return null;el.checked=$checked;" +
                "el.dispatchEvent(new Event('change',{bubbles:true}));" +
                "return{tag:el.tagName.toLowerCase(),checked:el.checked};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) {
                errorResponse("ELEMENT_NOT_FOUND", "No element matches: $selector")
            } else {
                ctx.showTouchIndicatorForElement(selector, ctx.overlayColor(body))
                successResponse(mapOf("element" to result))
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun calibratedTapExecution(
        requestedX: Double,
        requestedY: Double,
        calibration: TapCalibration,
    ): TapExecution {
        val viewport = viewportSize()
        val appliedX = clamp(requestedX + calibration.offsetX, 0.0, maxOf(viewport.first - 1.0, 0.0))
        val appliedY = clamp(requestedY + calibration.offsetY, 0.0, maxOf(viewport.second - 1.0, 0.0))
        return TapExecution(
            requestedX = requestedX,
            requestedY = requestedY,
            appliedX = appliedX,
            appliedY = appliedY,
            offsetX = calibration.offsetX,
            offsetY = calibration.offsetY,
        )
    }

    private suspend fun viewportSize(): Pair<Double, Double> {
        val result =
            ctx.evaluateJSReturningJSON(
                """
                (function() {
                    return {
                        width: Math.max(window.innerWidth || 0, 1),
                        height: Math.max(window.innerHeight || 0, 1)
                    };
                })()
                """.trimIndent(),
            )
        val width = (result["width"] as? Number)?.toDouble() ?: 1.0
        val height = (result["height"] as? Number)?.toDouble() ?: 1.0
        return width to height
    }

    private fun clamp(
        value: Double,
        lower: Double,
        upper: Double,
    ): Double =
        when {
            lower > upper -> lower
            value < lower -> lower
            value > upper -> upper
            else -> value
        }

    private fun tapScript(execution: TapExecution): String =
        """
        (function() {
            ${interactionHelpersScript()}
            var requestedX = ${execution.requestedX};
            var requestedY = ${execution.requestedY};
            var appliedX = ${execution.appliedX};
            var appliedY = ${execution.appliedY};
            var offsetX = ${execution.offsetX};
            var offsetY = ${execution.offsetY};
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
        })();
        """.trimIndent()
}
