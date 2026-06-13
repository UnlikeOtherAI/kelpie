import WebKit

/// Handles getNetworkLog and getResourceTimeline.
/// iOS has limited network visibility — uses Performance API (Resource Timing) for basic data.
struct NetworkHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("get-network-log") { body in await getNetworkLog(body) }
        router.register("get-resource-timeline") { body in await getResourceTimeline(body) }
    }

    @MainActor
    private func getNetworkLog(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        let typeFilter = body["type"] as? String
        let statusCategory = Self.parseStatusCategory(body["status"])
        let sinceFilter = Self.parseSinceMillis(body["since"])
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
            let jsonString = try await context.evaluateJSReturningString("JSON.stringify(\(js))", tabId: tabId)
            guard let data = jsonString.data(using: .utf8),
                  let rawArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return successResponse(["entries": [] as [Any], "count": 0, "hasMore": false, "summary": emptySummary()])
            }
            let array = applyRealDocumentStatus(to: rawArray)
            var filtered = array
            if let typeFilter {
                filtered = filtered.filter { ($0["type"] as? String) == typeFilter }
            }
            if let statusCategory {
                filtered = filtered.filter { Self.matchesStatusCategory($0["status"] as? Int, statusCategory) }
            }
            if let sinceFilter {
                filtered = filtered.filter {
                    guard let started = Self.entryStartedMillis($0) else { return false }
                    return started >= sinceFilter
                }
            }
            let limited = Array(filtered.prefix(limit))
            return successResponse([
                "entries": limited,
                "count": limited.count,
                "hasMore": filtered.count > limit,
                "summary": buildSummary(filtered)
            ])
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func getResourceTimeline(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
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
            let result = try await context.evaluateJSReturningJSON(js, tabId: tabId)
            return successResponse(result)
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    /// WebKit's Performance API does not populate `responseStatus` for main-frame
    /// document navigations, so those entries default to 200 even on a 404. The
    /// real status is captured from `WKNavigationResponse` in `NetworkTrafficStore`;
    /// overlay it onto the document entries here, matched by URL.
    @MainActor
    private func applyRealDocumentStatus(to entries: [[String: Any]]) -> [[String: Any]] {
        let documentStatuses = NetworkTrafficStore.shared.documentNavigationStatuses()
        guard !documentStatuses.isEmpty else { return entries }
        return entries.map { entry in
            guard (entry["type"] as? String) == "document",
                  let url = entry["url"] as? String,
                  let status = documentStatuses[url] else {
                return entry
            }
            var updated = entry
            updated["status"] = status
            updated["statusText"] = Self.reasonPhrase(for: status)
            return updated
        }
    }

    private static let reasonPhrases: [Int: String] = [
        200: "OK", 201: "Created", 204: "No Content",
        301: "Moved Permanently", 302: "Found", 304: "Not Modified",
        400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
        405: "Method Not Allowed", 408: "Request Timeout", 429: "Too Many Requests",
        500: "Internal Server Error", 502: "Bad Gateway",
        503: "Service Unavailable", 504: "Gateway Timeout"
    ]

    /// HTTP reason phrase for a status code, used to keep `statusText` consistent
    /// with the corrected document status.
    private static func reasonPhrase(for status: Int) -> String {
        reasonPhrases[status] ?? HTTPURLResponse.localizedString(forStatusCode: status).capitalized
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
            "loadTime": Int(maxEnd)
        ]
    }

    private func emptySummary() -> [String: Any] {
        ["totalRequests": 0, "totalSize": 0, "totalTransferSize": 0, "byType": [String: Int](), "errors": 0, "loadTime": 0]
    }

    /// Parse a `status` filter param into a category: "success", "error", or "pending"; nil when absent/invalid.
    private static func parseStatusCategory(_ value: Any?) -> String? {
        guard let category = (value as? String)?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
        switch category {
        case "success", "error", "pending": return category
        default: return nil
        }
    }

    /// Map an entry's HTTP status code to a category and test membership.
    /// "success" = final status 200–399; "error" = status >= 400 or failed; "pending" = no final status (0/missing).
    private static func matchesStatusCategory(_ status: Int?, _ category: String) -> Bool {
        switch category {
        case "success": return status.map { (200...399).contains($0) } ?? false
        case "error": return status.map { $0 >= 400 } ?? false
        case "pending": return status == nil || status == 0
        default: return false
        }
    }

    /// Parse a `since` param (epoch millis number or ISO-8601 string) into epoch millis, or nil when absent.
    private static func parseSinceMillis(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let stringValue = value as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespaces)
            if let millis = Double(trimmed) { return millis }
            return parseISO8601Millis(trimmed)
        }
        return nil
    }

    /// Convert an entry's `timing.started` ISO-8601 string into epoch millis.
    private static func entryStartedMillis(_ entry: [String: Any]) -> Double? {
        guard let timing = entry["timing"] as? [String: Any],
              let started = timing["started"] as? String else { return nil }
        return parseISO8601Millis(started)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601FormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseISO8601Millis(_ iso: String) -> Double? {
        if let date = iso8601Formatter.date(from: iso) { return date.timeIntervalSince1970 * 1000 }
        if let date = iso8601FormatterNoFraction.date(from: iso) { return date.timeIntervalSince1970 * 1000 }
        return nil
    }
}
