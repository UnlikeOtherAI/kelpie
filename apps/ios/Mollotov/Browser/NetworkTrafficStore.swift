import Foundation

/// Captures HTTP request/response traffic via JS injection for the network inspector.
final class NetworkTrafficStore: ObservableObject {
    static let shared = NetworkTrafficStore()

    struct TrafficEntry: Identifiable {
        let id: UUID
        let method: String
        let url: String
        let statusCode: Int
        let contentType: String
        let requestHeaders: [String: String]
        let responseHeaders: [String: String]
        let requestBody: String?
        let responseBody: String?
        let startTime: Date
        let duration: Int // ms
        let size: Int // bytes

        /// Simplified content type category for filtering.
        var category: String {
            if contentType.contains("json") { return "JSON" }
            if contentType.contains("html") { return "HTML" }
            if contentType.contains("css") { return "CSS" }
            if contentType.contains("javascript") || contentType.contains("ecmascript") { return "JS" }
            if contentType.contains("image") { return "Image" }
            if contentType.contains("font") { return "Font" }
            if contentType.contains("xml") { return "XML" }
            return "Other"
        }
    }

    @Published private(set) var entries: [TrafficEntry] = []
    /// Index of the entry currently being inspected in the UI (LLM can read this).
    @Published var selectedIndex: Int?

    var selectedEntry: TrafficEntry? {
        guard let idx = selectedIndex, entries.indices.contains(idx) else { return nil }
        return entries[idx]
    }

    private init() {}

    func append(_ entry: TrafficEntry) {
        entries.append(entry)
        if entries.count > 2000 { entries.removeFirst(entries.count - 2000) }
    }

    func clear() {
        entries.removeAll()
        selectedIndex = nil
    }

    func entryToJSON(_ entry: TrafficEntry) -> [String: Any] {
        [
            "id": entry.id.uuidString,
            "method": entry.method,
            "url": entry.url,
            "statusCode": entry.statusCode,
            "contentType": entry.contentType,
            "category": entry.category,
            "requestHeaders": entry.requestHeaders,
            "responseHeaders": entry.responseHeaders,
            "requestBody": entry.requestBody ?? "",
            "responseBody": entry.responseBody ?? "",
            "startTime": ISO8601DateFormatter().string(from: entry.startTime),
            "duration": entry.duration,
            "size": entry.size,
        ]
    }

    func toSummaryJSON(method: String? = nil, category: String? = nil, statusRange: String? = nil, urlPattern: String? = nil) -> [[String: Any]] {
        var filtered = entries
        if let m = method { filtered = filtered.filter { $0.method == m.uppercased() } }
        if let c = category { filtered = filtered.filter { $0.category.lowercased() == c.lowercased() } }
        if let pattern = urlPattern { filtered = filtered.filter { $0.url.contains(pattern) } }
        if let range = statusRange {
            let parts = range.split(separator: "-").compactMap { Int($0) }
            if parts.count == 2 {
                filtered = filtered.filter { $0.statusCode >= parts[0] && $0.statusCode <= parts[1] }
            } else if parts.count == 1 {
                filtered = filtered.filter { $0.statusCode == parts[0] }
            }
        }
        return filtered.enumerated().map { (idx, e) in
            ["index": idx, "method": e.method, "url": e.url,
             "statusCode": e.statusCode, "contentType": e.contentType,
             "category": e.category, "duration": e.duration, "size": e.size]
        }
    }
}
