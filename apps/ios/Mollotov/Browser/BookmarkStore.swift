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
    }

    @Published private(set) var bookmarks: [Bookmark] = []
    private let key = "mollotov_bookmarks"

    private init() { load() }

    func add(title: String, url: String) {
        bookmarks.append(Bookmark(title: title, url: url))
        save()
    }

    func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    func removeAll() {
        bookmarks.removeAll()
        save()
    }

    func toJSON() -> [[String: Any]] {
        bookmarks.map { b in
            ["id": b.id.uuidString, "title": b.title, "url": b.url,
             "createdAt": ISO8601DateFormatter().string(from: b.createdAt)]
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) else { return }
        bookmarks = decoded
    }
}
