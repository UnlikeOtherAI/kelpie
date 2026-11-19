import Foundation

enum NetworkDiagnosticEntries {
    static let snapshotScript = #"""
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
    """#

    private struct ResourceKey: Hashable {
        let url: String
        let type: String

        init?(_ entry: [String: Any]) {
            guard let url = entry["url"] as? String, !url.isEmpty, let type = entry["type"] as? String else { return nil }
            self.url = url
            self.type = type
        }
    }

    static func merge(
        _ entries: [[String: Any]],
        captured: [[String: Any]],
        documentStart: Double,
        documentResponse: (url: String, status: Int, mimeType: String)?
    ) -> [[String: Any]] {
        var output = entries
        var candidates: [ResourceKey: [(index: Int, started: Double)]] = [:]
        for (index, entry) in entries.enumerated() {
            guard let key = ResourceKey(entry) else { continue }
            if key.type == "document", let response = documentResponse, key.url == response.url, response.status > 0 {
                output[index]["status"] = response.status
                if !response.mimeType.isEmpty { output[index]["mimeType"] = response.mimeType }
            }
            if key.type == "xhr" || key.type == "fetch",
               let timing = entry["timing"] as? [String: Any], let timestamp = timing["started"] as? String,
               let started = NetworkHandler.parseISO8601Millis(timestamp) {
                candidates[key, default: []].append((index, started))
            }
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for event in captured.sorted(by: { ($0["started"] as? Double ?? 0) < ($1["started"] as? Double ?? 0) }) {
            guard let key = ResourceKey(event), let started = event["started"] as? Double,
                  started >= documentStart, started.isFinite else { continue }
            let status = event["statusCode"] as? Int ?? 0
            let timings = candidates[key] ?? []
            // Compare starts as well as URL/type so repeated requests retain their own method and status.
            let match = timings.indices.filter {
                let measuredStatus = output[timings[$0].index]["status"] as? Int
                return abs(timings[$0].started - started) <= 16
                    && (measuredStatus == nil || status == 0 || measuredStatus == status)
            }.min { abs(timings[$0].started - started) < abs(timings[$1].started - started) }
            var entry: [String: Any]
            if let match {
                let index = timings[match].index
                candidates[key]?.remove(at: match)
                entry = output[index]
                applyCapture(event, status: status, to: &entry)
                output[index] = entry
            } else {
                entry = [
                    "url": key.url, "type": key.type, "method": NSNull(), "status": NSNull(),
                    "statusText": NSNull(), "mimeType": NSNull(), "size": NSNull(), "transferSize": NSNull(),
                    "initiator": key.type == "xhr" ? "xmlhttprequest" : key.type,
                    "timing": [
                        "started": formatter.string(from: Date(timeIntervalSince1970: started / 1000)),
                        "total": max(0, event["duration"] as? Int ?? 0)
                    ]
                ]
                applyCapture(event, status: status, to: &entry)
                output.append(entry)
            }
        }
        return output
    }

    private static func applyCapture(_ event: [String: Any], status: Int, to entry: inout [String: Any]) {
        if let method = event["method"] as? String, !method.isEmpty { entry["method"] = method }
        if status > 0 { entry["status"] = status }
        if let reason = event["statusText"] as? String, !reason.isEmpty { entry["statusText"] = reason }
        if let mimeType = event["contentType"] as? String, !mimeType.isEmpty { entry["mimeType"] = mimeType }
        if let failure = event["failure"] as? String { entry["failure"] = failure }
    }
}
