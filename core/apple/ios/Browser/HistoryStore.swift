import Foundation

/// Persists history via the shared native core-state library.
/// Xcode still needs the bridge and static libs configured manually; see apps/ios/NATIVE_INTEGRATION.md.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    struct HistoryEntry: Identifiable, Codable {
        let id: UUID
        let url: String
        var title: String
        let timestamp: Date

        init(url: String, title: String) {
            self.id = UUID()
            self.url = url
            self.title = title
            self.timestamp = Date()
        }

        init(id: UUID, url: String, title: String, timestamp: Date) {
            self.id = id
            self.url = url
            self.title = title
            self.timestamp = timestamp
        }
    }

    @Published private(set) var entries: [HistoryEntry] = []
    private(set) var clearGeneration = 0

    private static let maxEntries = 500
    private let key = "kelpie_history"
    private let handle: KelpieHistoryStoreRef

    private init() {
        guard let handle = kelpie_history_store_create() else {
            fatalError("Failed to create Kelpie history store")
        }

        self.handle = handle
        bootstrapFromPersistence()
        refreshPublishedEntries()
    }

    deinit {
        kelpie_history_store_destroy(handle)
    }

    func record(url: String, title: String) {
        url.withCString { urlPointer in
            title.withCString { titlePointer in
                kelpie_history_store_record(handle, urlPointer, titlePointer)
            }
        }
        persistAndRefresh()
    }

    func clear() {
        kelpie_history_store_clear(handle)
        clearGeneration += 1
        persistAndRefresh()
    }

    func updateLatestTitle(for url: String, title: String) {
        url.withCString { urlPointer in
            title.withCString { titlePointer in
                kelpie_history_store_update_latest_title(handle, urlPointer, titlePointer)
            }
        }
        persistAndRefresh()
    }

    func bestURLCompletion(for query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return trimmed.withCString { queryPointer in
            guard let pointer = kelpie_history_store_best_url_completion(handle, queryPointer) else {
                return nil
            }
            defer { kelpie_free_string(pointer) }
            let result = String(cString: pointer)
            return result.isEmpty ? nil : result
        }
    }

    func toJSON() -> [[String: Any]] {
        entries.reversed().map { entry in
            [
                "id": entry.id.uuidString,
                "url": entry.url,
                "title": entry.title,
                "timestamp": Self.iso8601Formatter.string(from: entry.timestamp)
            ]
        }
    }

    private func bootstrapFromPersistence() {
        guard let data = persistedData(),
              let persistedEntries = decodeCurrentEntries(from: data) ?? decodeLegacyEntries(from: data),
              let json = encodeEntriesForNative(persistedEntries) else {
            return
        }

        json.withCString { jsonPointer in
            kelpie_history_store_load_json(handle, jsonPointer)
        }
        persistChronologicalEntries(persistedEntries)
    }

    private func persistAndRefresh() {
        guard let nativeJSON = copyNativeJSON() else {
            return
        }

        refreshPublishedEntries(from: nativeJSON)
        persistChronologicalEntries(entries)
    }

    private func refreshPublishedEntries() {
        refreshPublishedEntries(from: copyNativeJSON())
    }

    private func refreshPublishedEntries(from json: String?) {
        guard let json,
              let data = json.data(using: .utf8),
              var newestFirst = decodeNewestFirstEntries(from: data) else {
            entries = []
            return
        }

        if newestFirst.count > Self.maxEntries {
            newestFirst = Array(newestFirst.prefix(Self.maxEntries))
        }
        entries = Array(newestFirst.reversed())
    }

    private func copyNativeJSON() -> String? {
        guard let pointer = kelpie_history_store_to_json(handle) else {
            return nil
        }

        defer { kelpie_free_string(pointer) }
        return String(cString: pointer)
    }

    private func persistChronologicalEntries(_ entries: [HistoryEntry]) {
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

    private func decodeNewestFirstEntries(from data: Data) -> [HistoryEntry]? {
        let decoder = Self.iso8601Decoder()
        return try? decoder.decode([PersistedHistoryEntry].self, from: data).map(\.historyEntry)
    }

    private func decodeCurrentEntries(from data: Data) -> [HistoryEntry]? {
        let decoder = Self.iso8601Decoder()
        return try? decoder.decode([PersistedHistoryEntry].self, from: data).map(\.historyEntry)
    }

    private func decodeLegacyEntries(from data: Data) -> [HistoryEntry]? {
        let decoder = JSONDecoder()
        return try? decoder.decode([HistoryEntry].self, from: data)
    }

    private func encodeEntriesForNative(_ entries: [HistoryEntry]) -> String? {
        let encoder = Self.iso8601Encoder()
        let persisted = entries.map(PersistedHistoryEntry.init)
        guard let data = try? encoder.encode(persisted) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private struct PersistedHistoryEntry: Codable {
        let id: UUID
        let url: String
        let title: String
        let timestamp: Date

        init(_ entry: HistoryEntry) {
            id = entry.id
            url = entry.url
            title = entry.title
            timestamp = entry.timestamp
        }

        var historyEntry: HistoryEntry {
            HistoryEntry(id: id, url: url, title: title, timestamp: timestamp)
        }
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
