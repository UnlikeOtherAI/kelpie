import Foundation

/// Captures HTTP traffic via the shared native core-state library.
/// Xcode still needs the bridge and static libs configured manually; see apps/ios/NATIVE_INTEGRATION.md.
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
        let duration: Int
        let size: Int
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
            guard !isSyncingSelectedIndex else { return }
            applySelectedIndex()
        }
    }

    var selectedEntry: TrafficEntry? {
        guard let idx = selectedIndex, entries.indices.contains(idx) else { return nil }
        return entries[idx]
    }

    private let key = "kelpie_network_traffic"
    private let handle: KelpieNetworkTrafficStoreRef
    private var isSyncingSelectedIndex = false

    private init() {
        guard let handle = kelpie_network_traffic_store_create() else {
            fatalError("Failed to create Kelpie network traffic store")
        }

        self.handle = handle
        bootstrapFromPersistence()
        refreshPublishedState()
    }

    deinit {
        kelpie_network_traffic_store_destroy(handle)
    }

    func append(_ entry: TrafficEntry) {
        guard let json = encodeEntryForNative(entry) else {
            return
        }

        let appended = json.withCString { jsonPointer in
            kelpie_network_traffic_store_append_json(handle, jsonPointer)
        }
        guard appended == 1 else { return }

        persistAndRefresh()
    }

    func appendDocumentNavigation(
        url: String,
        statusCode: Int,
        contentType: String,
        responseHeaders: [String: String] = [:],
        size: Int = 0,
        startedAt: Date
    ) {
        let headersJSON = encodeHeaders(responseHeaders) ?? "{}"
        let startTime = Self.iso8601Formatter.string(from: startedAt)
        let duration = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))

        url.withCString { urlPointer in
            contentType.withCString { contentTypePointer in
                headersJSON.withCString { headersPointer in
                    startTime.withCString { startTimePointer in
                        kelpie_network_traffic_store_append_document_navigation(
                            handle,
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

        persistAndRefresh()
    }

    func clear() {
        kelpie_network_traffic_store_clear(handle)
        persistAndRefresh()
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
        let json = withOptionalCString(method) { methodPointer in
            withOptionalCString(category) { categoryPointer in
                withOptionalCString(statusRange) { statusRangePointer in
                    withOptionalCString(urlPattern) { urlPatternPointer in
                        copyNativeString {
                            kelpie_network_traffic_store_to_summary_json(
                                handle,
                                methodPointer,
                                categoryPointer,
                                statusRangePointer,
                                urlPatternPointer
                            )
                        }
                    }
                }
            }
        }

        guard let json,
              let data = json.data(using: .utf8),
              let entries = try? Self.iso8601Decoder().decode([PersistedSummaryEntry].self, from: data) else {
            return []
        }

        return entries.map { entry in
            [
                "index": entry.index,
                "method": entry.method,
                "url": entry.url,
                "statusCode": entry.statusCode,
                "contentType": entry.contentType,
                "category": entry.category,
                "duration": entry.duration,
                "size": entry.size,
            ]
        }
    }

    private func bootstrapFromPersistence() {
        guard let data = persistedData(),
              let persistedEntries = decodeEntries(from: data),
              let json = encodeEntriesForNative(persistedEntries) else {
            return
        }

        json.withCString { jsonPointer in
            kelpie_network_traffic_store_load_json(handle, jsonPointer)
        }
        persistEntries(persistedEntries)
    }

    private func persistAndRefresh() {
        guard let nativeJSON = copyNativeEntriesJSON() else {
            return
        }

        refreshPublishedState(from: nativeJSON)
        persistEntries(entries)
    }

    private func refreshPublishedState() {
        refreshPublishedState(from: copyNativeEntriesJSON())
    }

    private func refreshPublishedState(from json: String?) {
        guard let json,
              let data = json.data(using: .utf8),
              let decoded = decodeEntries(from: data) else {
            entries = []
            syncSelectedIndexFromNative()
            return
        }

        entries = decoded
        syncSelectedIndexFromNative()
    }

    private func applySelectedIndex() {
        if let selectedIndex {
            let selected = kelpie_network_traffic_store_select(handle, Int32(selectedIndex))
            if selected == 1 {
                syncSelectedIndexFromNative()
                return
            }
        } else {
            clearNativeSelection()
        }

        syncSelectedIndexFromNative()
    }

    private func clearNativeSelection() {
        guard let json = encodeEntriesForNative(entries) else {
            return
        }

        // Reloading the same entries is the only exposed C API path that clears selection without
        // changing the entry list.
        json.withCString { jsonPointer in
            kelpie_network_traffic_store_load_json(handle, jsonPointer)
        }
    }

    private func syncSelectedIndexFromNative() {
        isSyncingSelectedIndex = true
        let nativeIndex = kelpie_network_traffic_store_selected_index(handle)
        selectedIndex = nativeIndex >= 0 ? Int(nativeIndex) : nil
        isSyncingSelectedIndex = false
    }

    private func copyNativeEntriesJSON() -> String? {
        copyNativeString { kelpie_network_traffic_store_to_json(handle) }
    }

    private func copyNativeString(_ producer: () -> UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer = producer() else {
            return nil
        }

        defer { kelpie_free_string(pointer) }
        return String(cString: pointer)
    }

    private func persistEntries(_ entries: [TrafficEntry]) {
        guard let json = encodeEntriesForNative(entries) else {
            return
        }
        UserDefaults.standard.set(Data(json.utf8), forKey: key)
    }

    private func persistedData() -> Data? {
        if let data = UserDefaults.standard.data(forKey: key) {
            return data
        }
        if let string = UserDefaults.standard.string(forKey: key) {
            return Data(string.utf8)
        }
        return nil
    }

    private func decodeEntries(from data: Data) -> [TrafficEntry]? {
        let decoder = Self.iso8601Decoder()
        return try? decoder.decode([PersistedTrafficEntry].self, from: data).map(\.trafficEntry)
    }

    private func encodeEntryForNative(_ entry: TrafficEntry) -> String? {
        let encoder = Self.iso8601Encoder()
        guard let data = try? encoder.encode(PersistedTrafficEntry(entry)) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func encodeEntriesForNative(_ entries: [TrafficEntry]) -> String? {
        let encoder = Self.iso8601Encoder()
        let persisted = entries.map(PersistedTrafficEntry.init)
        guard let data = try? encoder.encode(persisted) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func encodeHeaders(_ headers: [String: String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: headers, options: []) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func withOptionalCString<T>(_ value: String?, _ body: (UnsafePointer<CChar>?) -> T) -> T {
        guard let value else {
            return body(nil)
        }
        return value.withCString(body)
    }

    private struct PersistedTrafficEntry: Codable {
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
        let duration: Int
        let size: Int
        let initiator: String?

        init(_ entry: TrafficEntry) {
            id = entry.id
            method = entry.method
            url = entry.url
            statusCode = entry.statusCode
            contentType = entry.contentType
            requestHeaders = entry.requestHeaders
            responseHeaders = entry.responseHeaders
            requestBody = entry.requestBody
            responseBody = entry.responseBody
            startTime = entry.startTime
            duration = entry.duration
            size = entry.size
            initiator = entry.initiator
        }

        var trafficEntry: TrafficEntry {
            TrafficEntry(
                id: id,
                method: method,
                url: url,
                statusCode: statusCode,
                contentType: contentType,
                requestHeaders: requestHeaders,
                responseHeaders: responseHeaders,
                requestBody: requestBody,
                responseBody: responseBody,
                startTime: startTime,
                duration: duration,
                size: size,
                initiator: initiator ?? "browser"
            )
        }
    }

    private struct PersistedSummaryEntry: Codable {
        let index: Int
        let method: String
        let url: String
        let statusCode: Int
        let contentType: String
        let category: String
        let duration: Int
        let size: Int
    }

    private static let iso8601Formatter = ISO8601DateFormatter()

    private static func iso8601Decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func iso8601Encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
