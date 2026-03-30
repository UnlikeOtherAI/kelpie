package com.mollotov.browser.devtools

import com.mollotov.browser.handlers.HandlerContext
import com.mollotov.browser.network.Router
import com.mollotov.browser.network.errorResponse
import com.mollotov.browser.network.successResponse

class NetworkLogHandler(private val ctx: HandlerContext) {
    fun register(router: Router) {
        router.register("get-network-log") { getNetworkLog(it) }
        router.register("get-resource-timeline") { getResourceTimeline() }
    }

    private suspend fun getNetworkLog(body: Map<String, Any?>): Map<String, Any?> {
        val limit = (body["limit"] as? Int) ?: 200
        val js = """
(function(){
    var entries = performance.getEntriesByType('resource');
    var nav = performance.getEntriesByType('navigation');
    return JSON.stringify(nav.concat(entries).map(function(e){
        var type = 'other';
        if (e.entryType === 'navigation') type = 'document';
        else if (e.initiatorType === 'script') type = 'script';
        else if (e.initiatorType === 'link' || e.initiatorType === 'css') type = 'stylesheet';
        else if (e.initiatorType === 'img') type = 'image';
        else if (e.initiatorType === 'fetch') type = 'fetch';
        else if (e.initiatorType === 'xmlhttprequest') type = 'xhr';
        return {
            url: e.name, type: type, method: 'GET',
            status: e.responseStatus || 200, statusText: 'OK',
            size: e.decodedBodySize || 0, transferSize: e.transferSize || 0,
            timing: { started: new Date(performance.timeOrigin + e.startTime).toISOString(), total: Math.round(e.duration) },
            initiator: e.initiatorType || 'other'
        };
    }));
})()
"""
        return try {
            val entries = ctx.evaluateJSReturningArray(js.replace("\n", " "))
            val limited = entries.take(limit)
            successResponse(mapOf("entries" to limited, "count" to limited.size, "hasMore" to (entries.size > limit)))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getResourceTimeline(): Map<String, Any?> {
        val js = """
(function(){
    var nav = performance.getEntriesByType('navigation')[0] || {};
    var entries = performance.getEntriesByType('resource');
    return {
        pageUrl: location.href,
        navigationStart: new Date(performance.timeOrigin).toISOString(),
        domContentLoaded: Math.round(nav.domContentLoadedEventEnd || 0),
        domComplete: Math.round(nav.domComplete || 0),
        loadEvent: Math.round(nav.loadEventEnd || 0),
        resources: entries.map(function(e){
            var type = 'other';
            if (e.initiatorType === 'script') type = 'script';
            else if (e.initiatorType === 'link' || e.initiatorType === 'css') type = 'stylesheet';
            else if (e.initiatorType === 'img') type = 'image';
            else if (e.initiatorType === 'fetch') type = 'fetch';
            return { url: e.name, type: type, start: Math.round(e.startTime), end: Math.round(e.startTime + e.duration), status: e.responseStatus || 200 };
        })
    };
})()
"""
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js.replace("\n", " ")))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }
}
