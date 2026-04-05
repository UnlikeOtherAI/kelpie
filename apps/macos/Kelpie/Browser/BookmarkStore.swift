import Foundation

/// Persists bookmarks to UserDefaults; accessible from UI and API handlers.
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()

    struct Bookmark: Identifiable, Codable, Equatable {
        let id: UUID
        var title: String
        var url: String
        var createdAt: Date

        init(title: String, url: String) {
            self.id = UUID()
            self.title = title
            self.url = url
            self.createdAt = Date()
        }

        private enum EncodingKeys: String, CodingKey {
            case id
            case title
            case url
            case createdAt
        }

        private enum DecodingKeys: String, CodingKey {
            case id
            case title
            case url
            case createdAt
            case created_at
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DecodingKeys.self)

            let identifier = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
            id = UUID(uuidString: identifier) ?? UUID()
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
            createdAt = Self.decodeDate(from: container) ?? Date()
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: EncodingKeys.self)
            try container.encode(id.uuidString, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encode(url, forKey: .url)
            try container.encode(createdAt, forKey: .createdAt)
        }

        private static func decodeDate(from container: KeyedDecodingContainer<DecodingKeys>) -> Date? {
            if let date = try? container.decode(Date.self, forKey: .createdAt) {
                return date
            }
            if let string = try? container.decode(String.self, forKey: .createdAt),
               let date = BookmarkStore.iso8601Formatter.date(from: string) {
                return date
            }
            if let string = try? container.decode(String.self, forKey: .created_at),
               let date = BookmarkStore.iso8601Formatter.date(from: string) {
                return date
            }
            return nil
        }
    }

    @Published private(set) var bookmarks: [Bookmark] = []

    private let key = "kelpie_bookmarks"
    private let storeHandle = kelpie_bookmark_store_create()

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
        kelpie_bookmark_store_destroy(storeHandle)
    }

    func add(title: String, url: String) {
        guard let storeHandle else { return }
        title.withCString { titlePointer in
            url.withCString { urlPointer in
                kelpie_bookmark_store_add(storeHandle, titlePointer, urlPointer)
            }
        }
        refreshFromCore()
        persist()
    }

    func remove(id: UUID) {
        guard let storeHandle else { return }
        id.uuidString.withCString { idPointer in
            kelpie_bookmark_store_remove(storeHandle, idPointer)
        }
        refreshFromCore()
        persist()
    }

    func removeAll() {
        guard let storeHandle else { return }
        kelpie_bookmark_store_remove_all(storeHandle)
        refreshFromCore()
        persist()
    }

    func toJSON() -> [[String: Any]] {
        bookmarks.map { bookmark in
            [
                "id": bookmark.id.uuidString,
                "title": bookmark.title,
                "url": bookmark.url,
                "createdAt": Self.iso8601Formatter.string(from: bookmark.createdAt),
            ]
        }
    }

    private func load() {
        guard let storeHandle else { return }

        let persistedJSON = loadPersistedJSON() ?? "[]"
        persistedJSON.withCString { jsonPointer in
            kelpie_bookmark_store_load_json(storeHandle, jsonPointer)
        }
        refreshFromCore()
    }

    private func refreshFromCore() {
        guard let json = exportedJSON() else {
            bookmarks = []
            return
        }

        let decoded = Self.decodeBookmarks(from: json.data(using: .utf8) ?? Data())
        bookmarks = decoded ?? []
    }

    private func persist() {
        let payload = Self.jsonData(from: toJSON()) ?? Data("[]".utf8)
        UserDefaults.standard.set(payload, forKey: key)
    }

    private func exportedJSON() -> String? {
        guard let storeHandle else { return nil }
        guard let rawPointer = kelpie_bookmark_store_to_json(storeHandle) else { return nil }
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
        guard let decoded = Self.decodeBookmarks(from: data) else { return nil }
        return Self.makeJSONString(from: decoded.map(Self.persistedJSONObject))
    }

    private static func decodeBookmarks(from data: Data) -> [Bookmark]? {
        let decoder = JSONDecoder()
        return try? decoder.decode([Bookmark].self, from: data)
    }

    private static func persistedJSONObject(for bookmark: Bookmark) -> [String: Any] {
        [
            "id": bookmark.id.uuidString,
            "title": bookmark.title,
            "url": bookmark.url,
            "createdAt": iso8601Formatter.string(from: bookmark.createdAt),
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
