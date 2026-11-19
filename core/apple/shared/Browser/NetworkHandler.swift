import Foundation

struct NetworkHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("get-network-log") { body in await getNetworkLog(body) }
        router.register("get-resource-timeline") { body in await getResourceTimeline(body) }
    }

    @MainActor
    private func getNetworkLog(_ body: [String: Any]) async -> [String: Any] {
        do {
            let target = try context.diagnosticTarget(body)
            let page = try await Self.readSnapshot(target)
            let entries = NetworkDiagnosticEntries.merge(
                page["entries"] as? [[String: Any]] ?? [],
                captured: target.buffer.network,
                documentStart: page["timeOrigin"] as? Double ?? 0,
                documentResponse: target.buffer.documentResponse
            )
            return successResponse(Self.networkLog(entries, filters: body))
        } catch {
            return diagnosticErrorResponse(error)
        }
    }

    @MainActor
    private func getResourceTimeline(_ body: [String: Any]) async -> [String: Any] {
        do {
            let page = try await Self.readSnapshot(context.diagnosticTarget(body))
            return successResponse(page.filter { $0.key != "entries" && $0.key != "timeOrigin" })
        } catch {
            return diagnosticErrorResponse(error)
        }
    }

    @MainActor
    private static func readSnapshot(_ target: DiagnosticTarget) async throws -> [String: Any] {
        let result = try await target.evaluate("JSON.stringify(\(NetworkDiagnosticEntries.snapshotScript))")
        guard let string = result as? String, let data = string.data(using: .utf8),
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HandlerError.noWebView
        }
        return value
    }

    static func networkLog(_ entries: [[String: Any]], filters: [String: Any]) -> [String: Any] {
        let type = filters["type"] as? String
        let since = parseSinceMillis(filters["since"])
        let statusCategory = parseStatusCategory(filters["status"])
        let limit = max(0, filters["limit"] as? Int ?? 200)
        var totalSize = 0
        var totalTransfer = 0
        var byType: [String: Int] = [:]
        var errors = 0
        var loadTime = 0
        var matches: [[String: Any]] = []

        for entry in entries {
            let timing = entry["timing"] as? [String: Any]
            let status = entry["status"] as? Int
            let failed = entry["failure"] is String
            let entryType = entry["type"] as? String ?? "other"
            if let type, type != entryType { continue }
            if let since {
                guard let timestamp = timing?["started"] as? String,
                      let started = parseISO8601Millis(timestamp), started >= since else { continue }
            }
            totalSize += entry["size"] as? Int ?? 0
            totalTransfer += entry["transferSize"] as? Int ?? 0
            byType[entryType, default: 0] += 1
            if matchesStatusCategory(status, "error", failed: failed) { errors += 1 }
            loadTime = max(loadTime, timing?["total"] as? Int ?? 0)
            if let statusCategory, !matchesStatusCategory(status, statusCategory, failed: failed) { continue }
            matches.append(entry)
        }
        let limited = Array(matches.prefix(limit))
        return [
            "entries": limited, "count": limited.count, "hasMore": matches.count > limit,
            "summary": [
                "totalRequests": byType.values.reduce(0, +), "totalSize": totalSize, "totalTransferSize": totalTransfer,
                "byType": byType, "errors": errors, "loadTime": loadTime
            ]
        ]
    }

    /// Parse a `status` filter param into a category: "success", "error", or "pending"; nil when absent/invalid.
    static func parseStatusCategory(_ value: Any?) -> String? {
        guard let category = (value as? String)?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
        switch category {
        case "success", "error", "pending": return category
        default: return nil
        }
    }

    /// Map an entry's HTTP status code to a category and test membership.
    /// "success" = final status 200–399; "error" = status >= 400 or failed; "pending" = no final status (0/missing).
    static func matchesStatusCategory(_ status: Int?, _ category: String, failed: Bool = false) -> Bool {
        if failed { return category == "error" }
        switch category {
        case "success": return status.map { (200...399).contains($0) } ?? false
        case "error": return status.map { $0 >= 400 } ?? false
        case "pending": return status == nil || status == 0
        default: return false
        }
    }

    /// Parse a `since` param (epoch millis number or ISO-8601 string) into epoch millis, or nil when absent.
    static func parseSinceMillis(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let stringValue = value as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespaces)
            if let millis = Double(trimmed) { return millis }
            return parseISO8601Millis(trimmed)
        }
        return nil
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

    static func parseISO8601Millis(_ iso: String) -> Double? {
        if let date = iso8601Formatter.date(from: iso) { return date.timeIntervalSince1970 * 1000 }
        if let date = iso8601FormatterNoFraction.date(from: iso) { return date.timeIntervalSince1970 * 1000 }
        return nil
    }
}
