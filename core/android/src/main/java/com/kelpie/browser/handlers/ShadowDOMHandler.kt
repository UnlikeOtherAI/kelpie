package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse

class ShadowDOMHandler(
    private val context: HandlerContext,
) {
    fun register(router: Router) {
        router.register("query-shadow-dom") { body -> queryShadowDOM(body) }
        router.register("get-shadow-roots") { getShadowRoots() }
    }

    private suspend fun queryShadowDOM(body: Map<String, Any?>): Map<String, Any?> {
        val hostSelector = body["hostSelector"] as? String ?: return errorResponse("MISSING_PARAM", "hostSelector is required")
        val shadowSelector = body["shadowSelector"] as? String ?: "*"
        val pierce = body["pierce"] as? Boolean ?: true
        val safeHost = JSEscape.string(hostSelector)
        val safeShadow = JSEscape.string(shadowSelector)

        val js =
            """
            (function(){
                function findInShadow(host, sel, recurse) {
                    if (!host || !host.shadowRoot) return null;
                    var el = host.shadowRoot.querySelector(sel);
                    if (el) return el;
                    if (recurse) {
                        var all = host.shadowRoot.querySelectorAll('*');
                        for (var i = 0; i < all.length; i++) {
                            if (all[i].shadowRoot) {
                                var found = findInShadow(all[i], sel, true);
                                if (found) return found;
                            }
                        }
                    }
                    return null;
                }
                var host = document.querySelector('$safeHost');
                if (!host) return {found: false, error: 'Host element not found'};
                var el = findInShadow(host, '$safeShadow', $pierce);
                if (!el) return {found: false};
                var r = el.getBoundingClientRect();
                var tag = el.tagName.toLowerCase();
                return {
                    found: true,
                    element: {
                        tag: tag,
                        text: (el.textContent || '').trim().substring(0, 100),
                        shadowHost: '$safeHost',
                        rect: {x: r.x, y: r.y, width: r.width, height: r.height},
                        visible: r.width > 0 && r.height > 0,
                        interactable: ['a','button','input','select','textarea'].includes(tag)
                    }
                };
            })()
            """.trimIndent()

        return try {
            successResponse(context.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getShadowRoots(): Map<String, Any?> {
        val js =
            """
            (function(){
                var hosts = [];
                var all = document.querySelectorAll('*');
                for (var i = 0; i < all.length; i++) {
                    var el = all[i];
                    if (el.shadowRoot) {
                        var tag = el.tagName.toLowerCase();
                        hosts.push({
                            selector: tag + (el.id ? '#' + el.id : ''),
                            tag: tag,
                            mode: 'open',
                            childCount: el.shadowRoot.childElementCount
                        });
                    }
                }
                return {hosts: hosts, count: hosts.length};
            })()
            """.trimIndent()

        return try {
            successResponse(context.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }
}
