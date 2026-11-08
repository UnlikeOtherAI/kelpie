package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse

class CommentaryHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("show-commentary") { showCommentary(it) }
        router.register("hide-commentary") { hideCommentary() }
    }

    private suspend fun showCommentary(body: Map<String, Any?>): Map<String, Any?> {
        val text = body["text"] as? String ?: return errorResponse("MISSING_PARAM", "text is required")
        if (text.isBlank()) return errorResponse("MISSING_PARAM", "text is required")
        val durationMs = (body["durationMs"] as? Int) ?: 3000
        val position = body["position"] as? String ?: "bottom"
        val positionCss =
            when (position) {
                "top" -> "top:24px;left:50%;transform:translateX(-50%);"
                "center" -> "top:50%;left:50%;transform:translate(-50%,-50%);"
                else -> "bottom:24px;left:50%;transform:translateX(-50%);"
            }
        val autoDismiss =
            if (durationMs > 0) {
                """
                setTimeout(function() {
                    toast.style.opacity = '0';
                    setTimeout(function() { toast.remove(); }, 300);
                }, $durationMs);
                """.trimIndent()
            } else {
                ""
            }

        val js =
            """
            (function() {
                var existing = document.getElementById('__kelpie_commentary');
                if (existing) existing.remove();
                var toast = document.createElement('div');
                toast.id = '__kelpie_commentary';
                toast.textContent = '${JSEscape.string(text)}';
                toast.style.cssText = 'position:fixed;$positionCss' +
                    'max-width:390px;width:calc(100% - 32px);padding:14px 22px;border-radius:16px;' +
                    'background:rgba(0,0,0,0.5);color:#fff;font:15px/1.4 -apple-system,system-ui,sans-serif;' +
                    'text-align:center;pointer-events:none;z-index:2147483647;' +
                    'backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);' +
                    'transition:opacity 0.3s ease-out;opacity:0;';
                document.body.appendChild(toast);
                requestAnimationFrame(function() { toast.style.opacity = '1'; });
                $autoDismiss
            })();
            """.trimIndent()

        return try {
            ctx.evaluateJS(js)
            successResponse(
                mapOf(
                    "text" to text,
                    "position" to position,
                    "durationMs" to durationMs,
                ),
            )
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun hideCommentary(): Map<String, Any?> {
        val js =
            """
            (function() {
                var el = document.getElementById('__kelpie_commentary');
                if (!el) return;
                el.style.opacity = '0';
                setTimeout(function() { el.remove(); }, 300);
            })();
            """.trimIndent()
        runCatching { ctx.evaluateJS(js) }
        return successResponse()
    }
}
