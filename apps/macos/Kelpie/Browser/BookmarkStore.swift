import Foundation
import CryptoKit

/// Persists bookmarks to UserDefaults; accessible from UI and API handlers.
@MainActor
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
            case name
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DecodingKeys.self)

            let identifier = (try? container.decode(String.self, forKey: .id)) ?? ""
            url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
            let digest = Array(SHA256.hash(data: Data(url.utf8)).prefix(16))
            let stableID = digest.withUnsafeBytes { raw in UUID(uuid: raw.loadUnaligned(as: uuid_t.self)) }
            id = UUID(uuidString: identifier) ?? stableID
            title = (try? container.decode(String.self, forKey: .title))
                ?? (try? container.decode(String.self, forKey: .name)) ?? url
            createdAt = Self.decodeDate(from: container) ?? Date(timeIntervalSince1970: 0)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: EncodingKeys.self)
            try container.encode(id.uuidString, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encode(url, forKey: .url)
            try container.encode(BookmarkStore.iso8601Formatter.string(from: createdAt), forKey: .createdAt)
        }

        private static func decodeDate(from container: KeyedDecodingContainer<DecodingKeys>) -> Date? {
            if let date = try? container.decode(Date.self, forKey: .createdAt) {
                return date
            }
            if let string = try? container.decode(String.self, forKey: .createdAt),
               let date = BookmarkStore.date(from: string) {
                return date
            }
            if let string = try? container.decode(String.self, forKey: .created_at),
               let date = BookmarkStore.date(from: string) {
                return date
            }
            return nil
        }
    }

    @Published private(set) var bookmarks: [Bookmark] = []

    @Published private(set) var syncError: String?
    @Published private(set) var isSyncing = false
    private var accountBookmarks: AccountBookmarks?

    func useAccount(_ account: UOAAccount) {
        accountBookmarks?.invalidate()
        bookmarks = []
        accountBookmarks = AccountBookmarks(account: account, store: self)
        accountBookmarks?.enqueue()
    }

    func useLocalBookmarks() {
        accountBookmarks?.invalidate()
        accountBookmarks = nil
        syncError = nil
        isSyncing = false
        load()
    }

    func refreshAccountBookmarks() { accountBookmarks?.enqueue() }
    func flush() async throws {
        let current = accountBookmarks
        try await current?.flush()
        guard current === accountBookmarks else { throw CancellationError() }
        if let syncError { throw NSError(domain: "UOABookmarks", code: 1, userInfo: [NSLocalizedDescriptionKey: syncError]) }
    }
    func setAccountBookmarks(_ value: [Bookmark]) { bookmarks = value }
    func setSyncState(busy: Bool, error: String?) { isSyncing = busy; syncError = error }

    private let defaults: UserDefaults
    private let key = "kelpie_bookmarks"
    private let storeHandle = kelpie_bookmark_store_create()

    nonisolated fileprivate static func date(from value: String) -> Date? {
        if let date = iso8601Formatter.date(from: value) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }

    nonisolated fileprivate static var iso8601Formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    deinit {
        kelpie_bookmark_store_destroy(storeHandle)
    }

    @discardableResult
    func add(title: String, url: String) -> Task<Void, Error>? {
        if let accountBookmarks {
            return accountBookmarks.enqueue(.add(Bookmark(title: title, url: url)))
        }
        guard let storeHandle else { return nil }
        title.withCString { titlePointer in
            url.withCString { urlPointer in
                kelpie_bookmark_store_add(storeHandle, titlePointer, urlPointer)
            }
        }
        refreshFromCore()
        persist()
        return nil
    }

    /// Shared by the active-window shortcut and chrome actions; never save the start page.
    @discardableResult
    func addPage(title: String, url: String, isStartPage: Bool) -> Bool {
        guard !isStartPage, let pageURL = URL(string: url),
              ["http", "https"].contains(pageURL.scheme?.lowercased() ?? ""),
              let host = pageURL.host, !host.isEmpty,
              !bookmarks.contains(where: { $0.url == pageURL.absoluteString }) else { return false }
        add(title: title.isEmpty ? pageURL.absoluteString : title, url: pageURL.absoluteString)
        return true
    }

    @discardableResult
    func remove(id: UUID) -> Task<Void, Error>? {
        if let accountBookmarks { return accountBookmarks.enqueue(.remove(id)) }
        guard let storeHandle else { return nil }
        id.uuidString.withCString { idPointer in
            kelpie_bookmark_store_remove(storeHandle, idPointer)
        }
        refreshFromCore()
        persist()
        return nil
    }

    @discardableResult
    func removeAll() -> Task<Void, Error>? {
        if let accountBookmarks { return accountBookmarks.enqueue(.clear) }
        guard let storeHandle else { return nil }
        kelpie_bookmark_store_remove_all(storeHandle)
        refreshFromCore()
        persist()
        return nil
    }

    func toJSON() -> [[String: Any]] {
        bookmarks.map { bookmark in
            [
                "id": bookmark.id.uuidString,
                "title": bookmark.title,
                "url": bookmark.url,
                "createdAt": Self.iso8601Formatter.string(from: bookmark.createdAt)
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
        defaults.set(payload, forKey: key)
    }

    private func exportedJSON() -> String? {
        guard let storeHandle else { return nil }
        guard let rawPointer = kelpie_bookmark_store_to_json(storeHandle) else { return nil }
        defer { kelpie_free_string(rawPointer) }
        return String(cString: rawPointer)
    }

    private func loadPersistedJSON() -> String? {
        if let data = defaults.data(forKey: key) {
            return normalizedPersistedJSON(from: data)
        }

        if let string = defaults.string(forKey: key) {
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
            "createdAt": iso8601Formatter.string(from: bookmark.createdAt)
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
