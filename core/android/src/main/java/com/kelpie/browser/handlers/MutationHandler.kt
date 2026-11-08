package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse

class MutationHandler(
    private val context: HandlerContext,
) {
    fun register(router: Router) {
        router.register("watch-mutations") { body -> watchMutations(body) }
        router.register("get-mutations") { body -> getMutations(body) }
        router.register("stop-watching") { body -> stopWatching(body) }
    }

    private suspend fun watchMutations(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: "body"
        val attributes = body["attributes"] as? Boolean ?: true
        val childList = body["childList"] as? Boolean ?: true
        val subtree = body["subtree"] as? Boolean ?: true
        val characterData = body["characterData"] as? Boolean ?: false
        val safeSelector = JSEscape.string(selector)

        val js =
            """
            (function(){
                if (!window.__kelpieMutations) window.__kelpieMutations = {};
                var id = 'mut_' + (crypto.randomUUID ? crypto.randomUUID() : Date.now() + '_' + Math.random().toString(36).slice(2));
                var buffer = [];
                var target = document.querySelector('$safeSelector');
                if (!target) return null;
                var observer = new MutationObserver(function(mutations) {
                    mutations.forEach(function(m) {
                        var entry = {
                            type: m.type,
                            target: m.target.tagName ? m.target.tagName.toLowerCase() + (m.target.className ? '.' + m.target.className.split(' ')[0] : '') : 'text',
                            timestamp: new Date().toISOString()
                        };
                        if (m.type === 'childList') {
                            entry.added = Array.from(m.addedNodes).filter(function(n){return n.nodeType===1;}).map(function(n){
                                return {tag: n.tagName.toLowerCase(), class: n.className || '', text: (n.textContent||'').trim().substring(0,50)};
                            });
                            entry.removed = Array.from(m.removedNodes).filter(function(n){return n.nodeType===1;}).map(function(n){
                                return {tag: n.tagName.toLowerCase(), class: n.className || '', text: (n.textContent||'').trim().substring(0,50)};
                            });
                        } else if (m.type === 'attributes') {
                            entry.attribute = m.attributeName;
                            entry.oldValue = m.oldValue;
                            entry.newValue = m.target.getAttribute(m.attributeName);
                        } else if (m.type === 'characterData') {
                            entry.oldValue = m.oldValue;
                            entry.newValue = m.target.textContent;
                        }
                        buffer.push(entry);
                        if (buffer.length > 1000) buffer.shift();
                    });
                });
                observer.observe(target, {
                    attributes: $attributes,
                    childList: $childList,
                    subtree: $subtree,
                    characterData: $characterData,
                    attributeOldValue: $attributes,
                    characterDataOldValue: $characterData
                });
                window.__kelpieMutations[id] = {observer: observer, buffer: buffer};
                return {watchId: id, watching: true};
            })()
            """.trimIndent()

        return try {
            val result = context.evaluateJSReturningJSON(js)
            if (result.isEmpty()) {
                errorResponse("ELEMENT_NOT_FOUND", "Target element not found: $selector")
            } else {
                successResponse(result)
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getMutations(body: Map<String, Any?>): Map<String, Any?> {
        val watchId = body["watchId"] as? String ?: return errorResponse("MISSING_PARAM", "watchId is required")
        val clear = body["clear"] as? Boolean ?: true
        val safeId = JSEscape.string(watchId)
        val js =
            """
            (function(){
                var w = (window.__kelpieMutations || {})['$safeId'];
                if (!w) return null;
                var mutations = w.buffer.slice();
                if ($clear) w.buffer.length = 0;
                return {mutations: mutations, count: mutations.length, hasMore: false};
            })()
            """.trimIndent()

        return try {
            val result = context.evaluateJSReturningJSON(js)
            if (result.isEmpty()) {
                errorResponse("WATCH_NOT_FOUND", "Watch $watchId not found")
            } else {
                successResponse(result)
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun stopWatching(body: Map<String, Any?>): Map<String, Any?> {
        val watchId = body["watchId"] as? String ?: return errorResponse("MISSING_PARAM", "watchId is required")
        val safeId = JSEscape.string(watchId)
        val js =
            """
            (function(){
                var w = (window.__kelpieMutations || {})['$safeId'];
                if (!w) return null;
                w.observer.disconnect();
                var total = w.buffer.length;
                delete window.__kelpieMutations['$safeId'];
                return {totalMutations: total};
            })()
            """.trimIndent()

        return try {
            val result = context.evaluateJSReturningJSON(js)
            if (result.isEmpty()) {
                errorResponse("WATCH_NOT_FOUND", "Watch $watchId not found")
            } else {
                successResponse(result)
            }
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }
}
