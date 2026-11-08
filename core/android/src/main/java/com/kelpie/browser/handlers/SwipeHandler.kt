package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import kotlinx.coroutines.delay

class SwipeHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("swipe") { swipe(it) }
    }

    private suspend fun swipe(body: Map<String, Any?>): Map<String, Any?> {
        val from = point(body["from"]) ?: return errorResponse("MISSING_PARAM", "from: {x,y} and to: {x,y} are required")
        val to = point(body["to"]) ?: return errorResponse("MISSING_PARAM", "from: {x,y} and to: {x,y} are required")
        val durationMs = maxOf((body["durationMs"] as? Int) ?: 400, 1)
        val steps = maxOf((body["steps"] as? Int) ?: 20, 1)
        val color = body["color"] as? String ?: "#3B82F6"

        try {
            ctx.evaluateJS(
                swipeTrailScript(
                    fromX = from.first,
                    fromY = from.second,
                    toX = to.first,
                    toY = to.second,
                    durationMs = durationMs,
                    color = color,
                ),
            )
        } catch (e: Exception) {
            return errorResponse("WEBVIEW_ERROR", e.message ?: "Unknown error")
        }

        val stepDelay = maxOf(durationMs / steps, 1)
        for (step in 0..steps) {
            if (ctx.scriptPlaybackState?.isAbortRequested() == true) break
            val progress = step.toDouble() / steps.toDouble()
            val currentX = from.first + (to.first - from.first) * progress
            val currentY = from.second + (to.second - from.second) * progress
            try {
                ctx.evaluateJS(
                    pointerEventScript(
                        step = step,
                        totalSteps = steps,
                        x = currentX,
                        y = currentY,
                    ),
                )
            } catch (e: Exception) {
                return errorResponse("WEBVIEW_ERROR", e.message ?: "Unknown error")
            }
            if (step < steps) {
                delay(stepDelay.toLong())
            }
        }

        return successResponse(
            mapOf(
                "from" to mapOf("x" to from.first, "y" to from.second),
                "to" to mapOf("x" to to.first, "y" to to.second),
                "durationMs" to durationMs,
                "steps" to steps,
                "direction" to swipeDirection(from.first, from.second, to.first, to.second),
            ),
        )
    }

    private fun point(value: Any?): Pair<Double, Double>? {
        val map = value as? Map<*, *> ?: return null
        val x = (map["x"] as? Number)?.toDouble() ?: return null
        val y = (map["y"] as? Number)?.toDouble() ?: return null
        return x to y
    }

    private fun swipeTrailScript(
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double,
        durationMs: Int,
        color: String,
    ): String {
        val trailDx = toX - fromX
        val trailDy = toY - fromY
        return """
            (function() {
                var existing = document.getElementById('__kelpie_swipe');
                if (existing) existing.remove();
                var root = document.createElement('div');
                root.id = '__kelpie_swipe';
                root.style.cssText = 'position:fixed;left:0;top:0;width:100%;height:100%;pointer-events:none;z-index:2147483647;';
                var trail = document.createElement('div');
                var length = Math.hypot($trailDx, $trailDy);
                var angle = Math.atan2($trailDy, $trailDx) * 180 / Math.PI;
                trail.style.cssText = 'position:absolute;left:${fromX}px;top:${fromY}px;width:' + length + 'px;height:6px;' +
                    'transform-origin:0 50%;transform:translateY(-50%) rotate(' + angle + 'deg);' +
                    'background:linear-gradient(90deg,${JSEscape.string(color)},transparent);border-radius:999px;opacity:0.65;';
                var dot = document.createElement('div');
                dot.style.cssText = 'position:absolute;left:${fromX}px;top:${fromY}px;width:26px;height:26px;margin-left:-13px;margin-top:-13px;' +
                    'border-radius:50%;background:${JSEscape.string(color)};box-shadow:0 0 0 4px rgba(255,255,255,0.2);' +
                    'transition:left ${durationMs}ms linear, top ${durationMs}ms linear;';
                root.appendChild(trail);
                root.appendChild(dot);
                document.body.appendChild(root);
                requestAnimationFrame(function() {
                    dot.style.left = '${toX}px';
                    dot.style.top = '${toY}px';
                });
                setTimeout(function() {
                    root.style.transition = 'opacity 0.2s ease-out';
                    root.style.opacity = '0';
                    setTimeout(function() { root.remove(); }, 220);
                }, ${durationMs + 120});
            })();
            """.trimIndent()
    }

    private fun pointerEventScript(
        step: Int,
        totalSteps: Int,
        x: Double,
        y: Double,
    ): String {
        val eventType =
            when (step) {
                0 -> "pointerdown"
                totalSteps -> "pointerup"
                else -> "pointermove"
            }
        return """
            (function() {
                var pointX = $x;
                var pointY = $y;
                var eventTarget = document.elementFromPoint(pointX, pointY) || document.body;
                if (window.PointerEvent) {
                    eventTarget.dispatchEvent(new PointerEvent('$eventType', {
                        bubbles: true,
                        clientX: pointX,
                        clientY: pointY,
                        pointerId: 1,
                        pointerType: 'touch',
                        isPrimary: true
                    }));
                } else {
                    var fallback = '$eventType' === 'pointerdown' ? 'mousedown' : ('$eventType' === 'pointerup' ? 'mouseup' : 'mousemove');
                    eventTarget.dispatchEvent(new MouseEvent(fallback, {
                        bubbles: true,
                        clientX: pointX,
                        clientY: pointY
                    }));
                }
            })();
            """.trimIndent()
    }

    private fun swipeDirection(
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double,
    ): String {
        val dx = toX - fromX
        val dy = toY - fromY
        return when {
            dy <= -100 && kotlin.math.abs(dx) < 50 -> "up"
            dy >= 100 && kotlin.math.abs(dx) < 50 -> "down"
            dx <= -100 && kotlin.math.abs(dy) < 50 -> "left"
            dx >= 100 && kotlin.math.abs(dy) < 50 -> "right"
            else -> "diagonal"
        }
    }
}
