import WebKit

/// Handles getNetworkLog and getResourceTimeline.
/// iOS has limited network visibility — uses Performance API (Resource Timing) for basic data.
struct NetworkHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("get-network-log") { body in await getNetworkLog(body) }
        router.register("get-resource-timeline") { _ in await getResourceTimeline() }
    }

    @MainActor
    private func getNetworkLog(_ body: [String: Any]) async -> [String: Any] {
        let typeFilter = body["type"] as? String
        let limit = body["limit"] as? Int ?? 200
        let js = """
        (function(){
            var entries = performance.getEntriesByType('resource');
            var nav = performance.getEntriesByType('navigation');
            var all = nav.concat(entries);
            return all.map(function(e){
                var type = 'other';
                if (e.entryType === 'navigation') type = 'document';
                else if (e.initiatorType === 'script') type = 'script';
                else if (e.initiatorType === 'link' || e.initiatorType === 'css') type = 'stylesheet';
                else if (e.initiatorType === 'img') type = 'image';
                else if (e.initiatorType === 'xmlhttprequest') type = 'xhr';
                else if (e.initiatorType === 'fetch') type = 'fetch';
                else if (e.initiatorType === 'font' || (e.name && e.name.match(/\\.(woff2?|ttf|otf|eot)/))) type = 'font';
                return {
                    url: e.name,
                    type: type,
                    method: 'GET',
                    status: e.responseStatus || 200,
                    statusText: 'OK',
                    mimeType: '',
                    size: e.decodedBodySize || 0,
                    transferSize: e.transferSize || 0,
                    timing: {
                        started: new Date(performance.timeOrigin + e.startTime).toISOString(),
                        dnsLookup: Math.round(e.domainLookupEnd - e.domainLookupStart),
                        tcpConnect: Math.round(e.connectEnd - e.connectStart),
                        tlsHandshake: Math.round(e.secureConnectionStart > 0 ? e.connectEnd - e.secureConnectionStart : 0),
                        requestSent: Math.round(e.responseStart - e.requestStart),
                        waiting: Math.round(e.responseStart - e.requestStart),
                        contentDownload: Math.round(e.responseEnd - e.responseStart),
                        total: Math.round(e.duration)
                    },
                    initiator: e.initiatorType || 'other'
                };
            });
        })()
        """
        do {
            let jsonString = try await context.evaluateJSReturningString("JSON.stringify(\(js))")
            guard let data = jsonString.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return successResponse(["entries": [] as [Any], "count": 0, "hasMore": false, "summary": emptySummary()])
            }
            var filtered = array
            if let typeFilter {
                filtered = filtered.filter { ($0["type"] as? String) == typeFilter }
            }
            let limited = Array(filtered.prefix(limit))
            return successResponse([
                "entries": limited,
                "count": limited.count,
                "hasMore": filtered.count > limit,
                "summary": buildSummary(filtered),
            ])
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func getResourceTimeline() async -> [String: Any] {
        let js = """
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
                    else if (e.initiatorType === 'xmlhttprequest') type = 'xhr';
                    return {
                        url: e.name,
                        type: type,
                        start: Math.round(e.startTime),
                        end: Math.round(e.startTime + e.duration),
                        status: e.responseStatus || 200
                    };
                })
            };
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    private func buildSummary(_ entries: [[String: Any]]) -> [String: Any] {
        var totalSize = 0
        var totalTransfer = 0
        var byType: [String: Int] = [:]
        var errors = 0
        var maxEnd: Double = 0

        for entry in entries {
            totalSize += entry["size"] as? Int ?? 0
            totalTransfer += entry["transferSize"] as? Int ?? 0
            let type = entry["type"] as? String ?? "other"
            byType[type, default: 0] += 1
            let status = entry["status"] as? Int ?? 200
            if status >= 400 { errors += 1 }
            if let timing = entry["timing"] as? [String: Any], let total = timing["total"] as? Int {
                maxEnd = max(maxEnd, Double(total))
            }
        }

        return [
            "totalRequests": entries.count,
            "totalSize": totalSize,
            "totalTransferSize": totalTransfer,
            "byType": byType,
            "errors": errors,
            "loadTime": Int(maxEnd),
        ]
    }

    private func emptySummary() -> [String: Any] {
        ["totalRequests": 0, "totalSize": 0, "totalTransferSize": 0, "byType": [String: Int](), "errors": 0, "loadTime": 0]
    }
}
