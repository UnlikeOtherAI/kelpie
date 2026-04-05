import Foundation

/// In-memory navigation history with persistence to UserDefaults.
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

        private enum EncodingKeys: String, CodingKey {
            case id
            case url
            case title
            case timestamp
        }

        private enum DecodingKeys: String, CodingKey {
            case id
            case url
            case title
            case timestamp
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DecodingKeys.self)

            let identifier = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
            id = UUID(uuidString: identifier) ?? UUID()
            url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            timestamp = Self.decodeDate(from: container) ?? Date()
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: EncodingKeys.self)
            try container.encode(id.uuidString, forKey: .id)
            try container.encode(url, forKey: .url)
            try container.encode(title, forKey: .title)
            try container.encode(timestamp, forKey: .timestamp)
        }

        private static func decodeDate(from container: KeyedDecodingContainer<DecodingKeys>) -> Date? {
            if let date = try? container.decode(Date.self, forKey: .timestamp) {
                return date
            }
            if let string = try? container.decode(String.self, forKey: .timestamp),
               let date = HistoryStore.iso8601Formatter.date(from: string) {
                return date
            }
            return nil
        }
    }

    @Published private(set) var entries: [HistoryEntry] = []

    private let key = "kelpie_history"
    private let storeHandle = kelpie_history_store_create()

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
        kelpie_history_store_destroy(storeHandle)
    }

    func record(url: String, title: String) {
        guard let storeHandle else { return }
        url.withCString { urlPointer in
            title.withCString { titlePointer in
                kelpie_history_store_record(storeHandle, urlPointer, titlePointer)
            }
        }
        refreshFromCore()
        persist()
    }

    func clear() {
        guard let storeHandle else { return }
        kelpie_history_store_clear(storeHandle)
        refreshFromCore()
        persist()
    }

    func updateLatestTitle(for url: String, title: String) {
        guard let storeHandle else { return }
        url.withCString { urlPointer in
            title.withCString { titlePointer in
                kelpie_history_store_update_latest_title(storeHandle, urlPointer, titlePointer)
            }
        }
        refreshFromCore()
        persist()
    }

    func toJSON() -> [[String: Any]] {
        entries.reversed().map { entry in
            [
                "id": entry.id.uuidString,
                "url": entry.url,
                "title": entry.title,
                "timestamp": Self.iso8601Formatter.string(from: entry.timestamp),
            ]
        }
    }

    private func load() {
        guard let storeHandle else { return }

        let persistedJSON = loadPersistedJSON() ?? "[]"
        persistedJSON.withCString { jsonPointer in
            kelpie_history_store_load_json(storeHandle, jsonPointer)
        }
        refreshFromCore()
    }

    private func refreshFromCore() {
        guard let json = exportedJSON() else {
            entries = []
            return
        }

        let decoded = Self.decodeEntries(from: json.data(using: .utf8) ?? Data()) ?? []
        entries = Array(decoded.reversed())
    }

    private func persist() {
        let payload = Self.jsonData(from: entries.map(Self.persistedJSONObject)) ?? Data("[]".utf8)
        UserDefaults.standard.set(payload, forKey: key)
    }

    private func exportedJSON() -> String? {
        guard let storeHandle else { return nil }
        guard let rawPointer = kelpie_history_store_to_json(storeHandle) else { return nil }
        defer { kelpie_free_string(rawPointer) }
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

    private static func decodeEntries(from data: Data) -> [HistoryEntry]? {
        let decoder = JSONDecoder()
        return try? decoder.decode([HistoryEntry].self, from: data)
    }

    private static func persistedJSONObject(for entry: HistoryEntry) -> [String: Any] {
        [
            "id": entry.id.uuidString,
            "url": entry.url,
            "title": entry.title,
            "timestamp": iso8601Formatter.string(from: entry.timestamp),
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
}
