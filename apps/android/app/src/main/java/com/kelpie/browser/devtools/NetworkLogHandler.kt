package com.kelpie.browser.devtools

import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import java.time.Instant

class NetworkLogHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("get-network-log") { getNetworkLog(it) }
        router.register("get-resource-timeline") { getResourceTimeline() }
    }

    private suspend fun getNetworkLog(body: Map<String, Any?>): Map<String, Any?> {
        val typeFilter = body["type"] as? String
        val statusFilter = parseStatusFilter(body["status"])
        val sinceFilter = parseSinceMillis(body["since"])
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
        else if (e.initiatorType === 'font' || (e.name && e.name.match(/\.(woff2?|ttf|otf|eot)/))) type = 'font';
        return {
            url: e.name, type: type, method: 'GET',
            status: e.responseStatus || 200, statusText: 'OK', mimeType: '',
            size: e.decodedBodySize || 0, transferSize: e.transferSize || 0,
            timing: { started: new Date(performance.timeOrigin + e.startTime).toISOString(), total: Math.round(e.duration) },
            initiator: e.initiatorType || 'other'
        };
    }));
})()
"""
        return try {
            val entries = ctx.evaluateJSReturningArray(js.replace("\n", " "))
            var filtered = entries
            if (typeFilter != null) {
                filtered = filtered.filter { (it["type"] as? String) == typeFilter }
            }
            if (statusFilter != null) {
                filtered = filtered.filter { entryStatus(it) == statusFilter }
            }
            if (sinceFilter != null) {
                filtered = filtered.filter { entryStartedMillis(it)?.let { started -> started >= sinceFilter } ?: false }
            }
            val limited = filtered.take(limit)
            successResponse(
                mapOf(
                    "entries" to limited,
                    "count" to limited.size,
                    "hasMore" to (filtered.size > limit),
                    "summary" to buildSummary(filtered),
                ),
            )
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    /** Parse a status filter param into an exact HTTP status code, or null when absent/invalid. */
    private fun parseStatusFilter(value: Any?): Int? =
        when (value) {
            is Int -> value
            is Long -> value.toInt()
            is String -> value.trim().toIntOrNull()
            else -> null
        }

    /** Parse a `since` param (epoch millis number or ISO-8601 string) into epoch millis, or null when absent. */
    private fun parseSinceMillis(value: Any?): Long? =
        when (value) {
            is Long -> value
            is Int -> value.toLong()
            is Double -> value.toLong()
            is String -> value.trim().toLongOrNull() ?: parseIso8601Millis(value.trim())
            else -> null
        }

    private fun entryStatus(entry: Map<String, Any?>): Int? =
        when (val s = entry["status"]) {
            is Int -> s
            is Long -> s.toInt()
            is Double -> s.toInt()
            else -> null
        }

    private fun entryStartedMillis(entry: Map<String, Any?>): Long? {
        val timing = entry["timing"] as? Map<*, *> ?: return null
        val started = timing["started"] as? String ?: return null
        return parseIso8601Millis(started)
    }

    private fun parseIso8601Millis(iso: String): Long? =
        try {
            Instant.parse(iso).toEpochMilli()
        } catch (_: Exception) {
            null
        }

    /** Aggregate totals/byType/errors/loadTime over the filtered entries, mirroring iOS/macOS. */
    private fun buildSummary(entries: List<Map<String, Any?>>): Map<String, Any?> {
        var totalSize = 0L
        var totalTransfer = 0L
        val byType = mutableMapOf<String, Int>()
        var errors = 0
        var maxEnd = 0L

        for (entry in entries) {
            totalSize += numberAsLong(entry["size"])
            totalTransfer += numberAsLong(entry["transferSize"])
            val type = entry["type"] as? String ?: "other"
            byType[type] = (byType[type] ?: 0) + 1
            val status = entryStatus(entry) ?: 200
            if (status >= 400) errors++
            val timing = entry["timing"] as? Map<*, *>
            val total = numberAsLong(timing?.get("total"))
            if (total > maxEnd) maxEnd = total
        }

        return mapOf(
            "totalRequests" to entries.size,
            "totalSize" to totalSize,
            "totalTransferSize" to totalTransfer,
            "byType" to byType,
            "errors" to errors,
            "loadTime" to maxEnd,
        )
    }

    private fun numberAsLong(value: Any?): Long =
        when (value) {
            is Int -> value.toLong()
            is Long -> value
            is Double -> value.toLong()
            else -> 0L
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
