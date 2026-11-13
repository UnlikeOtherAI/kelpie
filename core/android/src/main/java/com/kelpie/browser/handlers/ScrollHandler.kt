package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse

class ScrollHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("scroll") { scroll(it) }
        router.register("scroll2") { scroll2(it) }
        router.register("scroll-to-top") { scrollTo(true) }
        router.register("scroll-to-bottom") { scrollTo(false) }
        router.register("scroll-to-y") { scrollToY(it) }
    }

    private suspend fun scroll(body: Map<String, Any?>): Map<String, Any?> {
        val dx = (body["deltaX"] as? Number)?.toDouble() ?: 0.0
        val dy = (body["deltaY"] as? Number)?.toDouble() ?: 0.0
        if (!dx.isFinite() || !dy.isFinite() || kotlin.math.abs(dx) > 10_000 || kotlin.math.abs(dy) > 10_000) {
            return errorResponse("INVALID_PARAMS", "Scroll delta must be finite and within 10000 pixels")
        }
        return try {
            val observed = ctx.evaluateJSReturningJSON(ScrollJavaScript.byDelta(dx, dy))
            if (observed.isEmpty()) {
                errorResponse("EVAL_ERROR", "Scroll was not evaluated by the renderer")
            } else {
                successResponse(observed)
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun scroll2(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val position = validScrollPosition(body["position"] as? String)
        val safe = JSEscape.string(selector)
        val js =
            "(function(){var el=document.querySelector('$safe');" +
                "if(!el)return null;el.scrollIntoView({block:'$position',behavior:'smooth'});" +
                "var r=el.getBoundingClientRect();" +
                "return{element:{tag:el.tagName.toLowerCase()," +
                "visible:r.top>=0&&r.bottom<=window.innerHeight," +
                "rect:{x:r.x,y:r.y,width:r.width,height:r.height}}," +
                "scrollsPerformed:1,viewport:{width:window.innerWidth,height:window.innerHeight}};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) {
                errorResponse("ELEMENT_NOT_FOUND", "Element not found: $selector")
            } else {
                ctx.showTouchIndicatorForElement(selector)
                successResponse(result)
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun scrollTo(top: Boolean): Map<String, Any?> =
        try {
            val observed = ctx.evaluateJSReturningJSON(ScrollJavaScript.edge(top))
            if (observed.isEmpty()) {
                errorResponse("EVAL_ERROR", "Scroll was not evaluated by the renderer")
            } else {
                successResponse(observed)
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }

    /**
     * Constrains scroll-into-view `block` value to the documented allowlist.
     * Anything else falls back to "center" — never interpolate raw input.
     */
    private fun validScrollPosition(raw: String?): String =
        when (raw) {
            "top", "center", "bottom" -> raw
            else -> "center"
        }

    private suspend fun scrollToY(body: Map<String, Any?>): Map<String, Any?> {
        val y =
            (body["y"] as? Number)?.toDouble()
                ?: return errorResponse("MISSING_PARAM", "y is required (pixel offset)")
        val x = (body["x"] as? Number)?.toDouble() ?: 0.0
        val js = "(function(){window.scrollTo($x,$y);return{scrollX:window.scrollX,scrollY:window.scrollY,maxScrollY:Math.max(0,document.documentElement.scrollHeight-window.innerHeight)};})()"
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }
}

/**
 * The handler context wraps its input inside JSON.stringify((expression)).
 * Multi-statement snippets must therefore be a *single IIFE expression*.
 * A semicolon-delimited top-level snippet silently produced empty results,
 * falsely reporting success for canonical page.scroll requests.
 */
internal object ScrollJavaScript {
    fun byDelta(
        dx: Double,
        dy: Double,
    ): String = "(function(){window.scrollBy($dx,$dy);return{scrollX:window.scrollX,scrollY:window.scrollY};})()"

    fun edge(top: Boolean): String =
        if (top) {
            "(function(){window.scrollTo(0,0);return{scrollX:window.scrollX,scrollY:window.scrollY};})()"
        } else {
            "(function(){window.scrollTo(0,document.documentElement.scrollHeight);" +
                "return{scrollX:window.scrollX,scrollY:window.scrollY};})()"
        }
}
