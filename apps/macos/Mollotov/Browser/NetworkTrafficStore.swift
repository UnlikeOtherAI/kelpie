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
        let initiator: String  // "browser" or "js"

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
    @Published var selectedIndex: Int? {
        didSet {
            syncSelectionToCore()
        }
    }

    var selectedEntry: TrafficEntry? {
        guard let idx = selectedIndex, entries.indices.contains(idx) else { return nil }
        return entries[idx]
    }

    private let key = "mollotov_network_traffic"
    private let storeHandle = mollotov_network_traffic_store_create()
    private var isSynchronizingSelection = false

    fileprivate static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private init() {
        load()
    }

    deinit {
        mollotov_network_traffic_store_destroy(storeHandle)
    }

    func append(_ entry: TrafficEntry) {
        guard let storeHandle else { return }
        guard let entryJSON = Self.makeJSONString(from: entryPayload(for: entry)) else { return }

        let appended = entryJSON.withCString { jsonPointer in
            mollotov_network_traffic_store_append_json(storeHandle, jsonPointer)
        }
        guard appended == 1 else { return }

        refreshFromCore()
        persist()
    }

    func appendDocumentNavigation(
        url: String,
        statusCode: Int,
        contentType: String,
        responseHeaders: [String: String] = [:],
        size: Int = 0,
        startedAt: Date
    ) {
        guard let storeHandle else { return }
        let headersJSON = Self.makeJSONString(from: responseHeaders) ?? "{}"
        let startTime = Self.iso8601Formatter.string(from: startedAt)
        let duration = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))

        url.withCString { urlPointer in
            contentType.withCString { contentTypePointer in
                headersJSON.withCString { headersPointer in
                    startTime.withCString { startTimePointer in
                        mollotov_network_traffic_store_append_document_navigation(
                            storeHandle,
                            urlPointer,
                            Int32(statusCode),
                            contentTypePointer,
                            headersPointer,
                            Int64(max(0, size)),
                            startTimePointer,
                            Int32(duration)
                        )
                    }
                }
            }
        }

        refreshFromCore()
        persist()
    }

    func clear() {
        guard let storeHandle else { return }
        mollotov_network_traffic_store_clear(storeHandle)
        refreshFromCore()
        persist()
    }

    func entryToJSON(_ entry: TrafficEntry) -> [String: Any] {
        [
            "id": entry.id.uuidString,
            "method": entry.method,
            "url": entry.url,
            "statusCode": entry.statusCode,
            "contentType": entry.contentType,
            "category": entry.category,
            "initiator": entry.initiator,
            "requestHeaders": entry.requestHeaders,
            "responseHeaders": entry.responseHeaders,
            "requestBody": entry.requestBody ?? "",
            "responseBody": entry.responseBody ?? "",
            "startTime": Self.iso8601Formatter.string(from: entry.startTime),
            "duration": entry.duration,
            "size": entry.size,
        ]
    }

    func toSummaryJSON(
        method: String? = nil,
        category: String? = nil,
        statusRange: String? = nil,
        urlPattern: String? = nil
    ) -> [[String: Any]] {
        guard let storeHandle else { return [] }

        var summaryJSON: String?
        Self.withOptionalCString(method) { methodPointer in
            Self.withOptionalCString(category) { categoryPointer in
                Self.withOptionalCString(statusRange) { statusRangePointer in
                    Self.withOptionalCString(urlPattern) { urlPatternPointer in
                        guard let rawPointer = mollotov_network_traffic_store_to_summary_json(
                            storeHandle,
                            methodPointer,
                            categoryPointer,
                            statusRangePointer,
                            urlPatternPointer
                        ) else {
                            return
                        }
                        defer { mollotov_free_string(rawPointer) }
                        summaryJSON = String(cString: rawPointer)
                    }
                }
            }
        }

        return Self.decodeSummary(from: summaryJSON)
    }

    private func load() {
        guard let storeHandle else { return }

        let persistedJSON = loadPersistedJSON() ?? "[]"
        persistedJSON.withCString { jsonPointer in
            mollotov_network_traffic_store_load_json(storeHandle, jsonPointer)
        }
        refreshFromCore()
    }

    private func refreshFromCore() {
        guard let json = exportedJSON() else {
            entries = []
            updateSelectedIndex(nil)
            return
        }

        entries = Self.decodeEntries(from: json) ?? []
        synchronizeSelectionFromCore()
    }

    private func persist() {
        let payload = Self.jsonData(from: entries.map { entryToJSON($0) }) ?? Data("[]".utf8)
        UserDefaults.standard.set(payload, forKey: key)
    }

    private func syncSelectionToCore() {
        guard !isSynchronizingSelection else { return }
        guard let storeHandle, let index = selectedIndex, entries.indices.contains(index) else { return }

        let selected = mollotov_network_traffic_store_select(storeHandle, Int32(index))
        if selected == 1 {
            synchronizeSelectionFromCore()
        }
    }

    private func synchronizeSelectionFromCore() {
        guard let storeHandle else {
            updateSelectedIndex(nil)
            return
        }

        let index = mollotov_network_traffic_store_selected_index(storeHandle)
        updateSelectedIndex(index >= 0 ? Int(index) : nil)
    }

    private func updateSelectedIndex(_ index: Int?) {
        isSynchronizingSelection = true
        selectedIndex = index
        isSynchronizingSelection = false
    }

    private func exportedJSON() -> String? {
        guard let storeHandle else { return nil }
        guard let rawPointer = mollotov_network_traffic_store_to_json(storeHandle) else { return nil }
        defer { mollotov_free_string(rawPointer) }
        return String(cString: rawPointer)
    }

    private func loadPersistedJSON() -> String? {
        if let data = UserDefaults.standard.data(forKey: key) {
            return normalizedPersistedJSON(from: data)
        }

        if let string = UserDefaults.standard.string(forKey: key) {
            return normalizedPersistedJSON(from: Data(string.utf8))
        }

        return nil
    }

    private func normalizedPersistedJSON(from data: Data) -> String? {
        guard let decoded = Self.decodeEntries(from: data) else { return nil }
        return Self.makeJSONString(from: decoded.map(Self.persistedJSONObject))
    }

    private func entryPayload(for entry: TrafficEntry) -> [String: Any] {
        var payload = entryToJSON(entry)
        if entry.requestBody == nil {
            payload["requestBody"] = NSNull()
        }
        if entry.responseBody == nil {
            payload["responseBody"] = NSNull()
        }
        return payload
    }

    private static func decodeEntries(from json: String?) -> [TrafficEntry]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return decodeEntries(from: data)
    }

    private static func decodeEntries(from data: Data) -> [TrafficEntry]? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let array = object as? [[String: Any]] else {
            return nil
        }

        return array.compactMap(Self.decodeEntry)
    }

    private static func decodeEntry(from object: [String: Any]) -> TrafficEntry? {
        let method = stringValue(in: object, keys: ["method"])
        let url = stringValue(in: object, keys: ["url"])
        guard let method, !method.isEmpty, let url, !url.isEmpty else { return nil }

        let identifier = stringValue(in: object, keys: ["id"]).flatMap(UUID.init(uuidString:)) ?? UUID()
        let startTime = dateValue(in: object, keys: ["start_time", "startTime"]) ?? Date()

        return TrafficEntry(
            id: identifier,
            method: method,
            url: url,
            statusCode: intValue(in: object, keys: ["status_code", "statusCode"]),
            contentType: stringValue(in: object, keys: ["content_type", "contentType"]) ?? "",
            requestHeaders: dictionaryValue(in: object, keys: ["request_headers", "requestHeaders"]),
            responseHeaders: dictionaryValue(in: object, keys: ["response_headers", "responseHeaders"]),
            requestBody: optionalStringValue(in: object, keys: ["request_body", "requestBody"]),
            responseBody: optionalStringValue(in: object, keys: ["response_body", "responseBody"]),
            startTime: startTime,
            duration: max(0, intValue(in: object, keys: ["duration"])),
            size: max(0, intValue(in: object, keys: ["size"])),
            initiator: stringValue(in: object, keys: ["initiator"]) ?? "browser"
        )
    }

    private static func decodeSummary(from json: String?) -> [[String: Any]] {
        guard let json, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let array = object as? [[String: Any]] else {
            return []
        }

        return array.map { item in
            [
                "index": intValue(in: item, keys: ["index"]),
                "method": stringValue(in: item, keys: ["method"]) ?? "",
                "url": stringValue(in: item, keys: ["url"]) ?? "",
                "statusCode": intValue(in: item, keys: ["status_code", "statusCode"]),
                "contentType": stringValue(in: item, keys: ["content_type", "contentType"]) ?? "",
                "category": stringValue(in: item, keys: ["category"]) ?? "",
                "duration": intValue(in: item, keys: ["duration"]),
                "size": intValue(in: item, keys: ["size"]),
            ]
        }
    }

    private static func persistedJSONObject(for entry: TrafficEntry) -> [String: Any] {
        [
            "id": entry.id.uuidString,
            "method": entry.method,
            "url": entry.url,
            "statusCode": entry.statusCode,
            "contentType": entry.contentType,
            "initiator": entry.initiator,
            "requestHeaders": entry.requestHeaders,
            "responseHeaders": entry.responseHeaders,
            "requestBody": entry.requestBody ?? NSNull(),
            "responseBody": entry.responseBody ?? NSNull(),
            "startTime": iso8601Formatter.string(from: entry.startTime),
            "duration": entry.duration,
            "size": entry.size,
        ]
    }

    private static func makeJSONString(from object: Any) -> String? {
        guard let data = jsonData(from: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func jsonData(from object: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object)
    }

    private static func withOptionalCString<Result>(
        _ value: String?,
        _ body: (UnsafePointer<CChar>?) -> Result
    ) -> Result {
        guard let value else { return body(nil) }
        return value.withCString(body)
    }

    private static func stringValue(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                return value
            }
        }
        return nil
    }

    private static func optionalStringValue(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if object[key] is NSNull {
                return nil
            }
            if let value = object[key] as? String {
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private static func intValue(in object: [String: Any], keys: [String]) -> Int {
        for key in keys {
            if let value = object[key] as? Int {
                return value
            }
            if let value = object[key] as? NSNumber {
                return value.intValue
            }
        }
        return 0
    }

    private static func dictionaryValue(in object: [String: Any], keys: [String]) -> [String: String] {
        for key in keys {
            guard let raw = object[key] as? [String: Any] else { continue }
            return raw.reduce(into: [:]) { result, element in
                if let value = element.value as? String {
                    result[element.key] = value
                }
            }
        }
        return [:]
    }

    private static func dateValue(in object: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let value = object[key] as? String,
               let date = iso8601Formatter.date(from: value) {
                return date
            }
            if let value = object[key] as? NSNumber {
                return Date(timeIntervalSinceReferenceDate: value.doubleValue)
            }
        }
        return nil
    }
}
