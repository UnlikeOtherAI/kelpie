import Foundation

/// Persists bookmarks via the shared native core-state library.
/// Xcode still needs the bridge and static libs configured manually; see apps/ios/NATIVE_INTEGRATION.md.
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

        init(id: UUID, title: String, url: String, createdAt: Date) {
            self.id = id
            self.title = title
            self.url = url
            self.createdAt = createdAt
        }
    }

    @Published private(set) var bookmarks: [Bookmark] = []

    private let key = "kelpie_bookmarks"
    private let handle: KelpieBookmarkStoreRef

    private init() {
        guard let handle = kelpie_bookmark_store_create() else {
            fatalError("Failed to create Kelpie bookmark store")
        }

        self.handle = handle
        bootstrapFromPersistence()
        refreshPublishedBookmarks()
    }

    deinit {
        kelpie_bookmark_store_destroy(handle)
    }

    func add(title: String, url: String) {
        title.withCString { titlePointer in
            url.withCString { urlPointer in
                kelpie_bookmark_store_add(handle, titlePointer, urlPointer)
            }
        }
        persistAndRefresh()
    }

    func remove(id: UUID) {
        let idString = id.uuidString
        idString.withCString { idPointer in
            kelpie_bookmark_store_remove(handle, idPointer)
        }
        persistAndRefresh()
    }

    func removeAll() {
        kelpie_bookmark_store_remove_all(handle)
        persistAndRefresh()
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

    private func bootstrapFromPersistence() {
        guard let data = persistedData(),
              let persistedBookmarks = decodeCurrentBookmarks(from: data) ?? decodeLegacyBookmarks(from: data),
              let json = encodeBookmarksForNative(persistedBookmarks) else {
            return
        }

        json.withCString { jsonPointer in
            kelpie_bookmark_store_load_json(handle, jsonPointer)
        }
        persist(json)
    }

    private func persistAndRefresh() {
        guard let nativeJSON = copyNativeJSON() else {
            return
        }

        persist(nativeJSON)
        refreshPublishedBookmarks(from: nativeJSON)
    }

    private func refreshPublishedBookmarks() {
        refreshPublishedBookmarks(from: copyNativeJSON())
    }

    private func refreshPublishedBookmarks(from json: String?) {
        guard let json,
              let data = json.data(using: .utf8),
              let decoded = decodeNativeBookmarks(from: data) else {
            bookmarks = []
            return
        }

        bookmarks = decoded
    }

    private func copyNativeJSON() -> String? {
        guard let pointer = kelpie_bookmark_store_to_json(handle) else {
            return nil
        }

        defer { kelpie_free_string(pointer) }
        return String(cString: pointer)
    }

    private func persist(_ json: String) {
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

    private func decodeNativeBookmarks(from data: Data) -> [Bookmark]? {
        let decoder = Self.iso8601Decoder()
        return try? decoder.decode([PersistedBookmark].self, from: data).map(\.bookmark)
    }

    private func decodeCurrentBookmarks(from data: Data) -> [Bookmark]? {
        decodeNativeBookmarks(from: data)
    }

    private func decodeLegacyBookmarks(from data: Data) -> [Bookmark]? {
        let decoder = JSONDecoder()
        return try? decoder.decode([Bookmark].self, from: data)
    }

    private func encodeBookmarksForNative(_ bookmarks: [Bookmark]) -> String? {
        let encoder = Self.iso8601Encoder()
        let persisted = bookmarks.map(PersistedBookmark.init)
        guard let data = try? encoder.encode(persisted) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private struct PersistedBookmark: Codable {
        let id: UUID
        let title: String
        let url: String
        let createdAt: Date

        init(_ bookmark: Bookmark) {
            id = bookmark.id
            title = bookmark.title
            url = bookmark.url
            createdAt = bookmark.createdAt
        }

        var bookmark: Bookmark {
            Bookmark(id: id, title: title, url: url, createdAt: createdAt)
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
