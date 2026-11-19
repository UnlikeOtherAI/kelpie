package com.kelpie.browser.devtools

import com.kelpie.browser.browser.DocumentResponse
import java.time.Instant
import kotlin.math.abs

internal const val NETWORK_SNAPSHOT = """
    (() => {
        const links = new Map();
        for (const link of document.querySelectorAll('link[href]')) {
            if (link.relList.contains('modulepreload')) links.set(link.href, 'script');
            else if (link.relList.contains('stylesheet')) links.set(link.href, 'stylesheet');
            else if (link.relList.contains('preload') && link.as) {
                links.set(link.href, link.as === 'style' ? 'stylesheet' : link.as);
            }
        }
        function resourceType(entry) {
            const initiator = entry.initiatorType;
            if (entry.entryType === 'navigation') return 'document';
            if (initiator === 'xmlhttprequest') return 'xhr';
            if (['fetch', 'script', 'font', 'audio', 'video'].includes(initiator)) return initiator;
            if (initiator === 'img' || initiator === 'image') return 'image';
            if (links.has(entry.name)) return links.get(entry.name);
            const mime = entry.contentType || '';
            if (mime === 'text/css') return 'stylesheet';
            if (mime.includes('javascript') || mime.includes('ecmascript')) return 'script';
            if (mime.startsWith('image/')) return 'image';
            if (mime.startsWith('font/')) return 'font';
            return 'other';
        }
        function elapsed(start, end, duration) {
            return start > 0 && end >= start && end - start <= duration ? Math.round(end - start) : null;
        }
        const nav = performance.getEntriesByType('navigation')[0];
        const resources = performance.getEntriesByType('resource');
        function status(entry) { return entry.responseStatus > 0 ? entry.responseStatus : null; }
        return {
            timeOrigin: performance.timeOrigin,
            pageUrl: location.href,
            navigationStart: new Date(performance.timeOrigin).toISOString(),
            domContentLoaded: Math.round(nav?.domContentLoadedEventEnd || 0),
            domComplete: Math.round(nav?.domComplete || 0),
            loadEvent: Math.round(nav?.loadEventEnd || 0),
            resources: resources.map(e => ({
                url: e.name, type: resourceType(e), status: status(e),
                start: Math.round(e.startTime), end: Math.round(e.startTime + e.duration)
            })),
            entries: (nav ? [nav, ...resources] : resources).map(e => ({
                url: e.name, type: resourceType(e), method: null,
                status: status(e), statusText: null, mimeType: e.contentType || null,
                size: e.decodedBodySize || null, transferSize: e.transferSize || null,
                timing: {
                    started: new Date(performance.timeOrigin + e.startTime).toISOString(),
                    dnsLookup: elapsed(e.domainLookupStart, e.domainLookupEnd, e.duration),
                    tcpConnect: elapsed(e.connectStart, e.connectEnd, e.duration),
                    tlsHandshake: elapsed(e.secureConnectionStart, e.connectEnd, e.duration),
                    requestSent: null,
                    waiting: elapsed(e.requestStart, e.responseStart, e.duration),
                    contentDownload: elapsed(e.responseStart, e.responseEnd, e.duration),
                    total: Math.round(e.duration)
                },
                initiator: e.initiatorType || 'other'
            }))
        };
    })()
"""

private data class ResourceKey(
    val url: String,
    val type: String,
)

private data class TimingCandidate(
    val index: Int,
    val started: Double,
)

private fun resourceKey(entry: Map<*, *>): ResourceKey? {
    val url = (entry["url"] as? String)?.takeIf(String::isNotEmpty) ?: return null
    val type = entry["type"] as? String ?: return null
    return ResourceKey(url, type)
}

internal fun mergeNetworkEntries(
    page: Map<String, Any?>,
    captured: List<Map<String, Any?>>,
    documentResponse: DocumentResponse?,
): List<Map<String, Any?>> {
    val documentStart = (page["timeOrigin"] as? Number)?.toDouble() ?: return emptyList()
    val candidates = mutableMapOf<ResourceKey, MutableList<TimingCandidate>>()
    val output = mutableListOf<MutableMap<String, Any?>>()
    for (raw in (page["entries"] as? List<*>).orEmpty()) {
        val entry =
            (raw as? Map<*, *>)?.mapNotNull { (key, value) -> (key as? String)?.let { it to value } }?.toMap()?.toMutableMap()
                ?: continue
        val key = resourceKey(entry) ?: continue
        if (key.type == "document" && documentResponse?.url == key.url) {
            entry["status"] = documentResponse.status
            documentResponse.mimeType?.let { entry["mimeType"] = it }
        }
        if (key.type == "xhr" || key.type == "fetch") {
            val timestamp = (entry["timing"] as? Map<*, *>)?.get("started") as? String
            val started = timestamp?.let { NetworkLogHandler.parseIso8601Millis(it) }
            if (started != null) {
                candidates.getOrPut(key) { mutableListOf() }.add(TimingCandidate(output.size, started.toDouble()))
            }
        }
        output.add(entry)
    }

    for (event in captured.sortedBy { it["started"] as? Double ?: 0.0 }) {
        val key = resourceKey(event) ?: continue
        val started = event["started"] as? Double ?: continue
        if (!started.isFinite() || started < documentStart) continue
        val status = event["statusCode"] as? Int ?: 0
        val timings = candidates[key]
        val match =
            timings
                ?.filter {
                    val measured = (output[it.index]["status"] as? Number)?.toInt()
                    abs(it.started - started) <= 16 && (measured == null || status == 0 || measured == status)
                }?.minByOrNull { abs(it.started - started) }
        val entry =
            if (match != null) {
                timings.remove(match)
                output[match.index]
            } else {
                mutableMapOf<String, Any?>(
                    "url" to key.url,
                    "type" to key.type,
                    "method" to null,
                    "status" to null,
                    "statusText" to null,
                    "mimeType" to null,
                    "size" to null,
                    "transferSize" to null,
                    "initiator" to if (key.type == "xhr") "xmlhttprequest" else key.type,
                    "timing" to
                        mapOf(
                            "started" to Instant.ofEpochMilli(started.toLong()).toString(),
                            "total" to (event["duration"] as? Int ?: 0).coerceAtLeast(0),
                        ),
                ).also { output.add(it) }
            }
        if (status > 0) entry["status"] = status
        for (field in listOf("method", "statusText", "mimeType", "failure")) {
            val value = (event[field] as? String)?.takeIf(String::isNotEmpty) ?: continue
            entry[field] = value
        }
    }
    return output
}
