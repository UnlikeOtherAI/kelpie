import Foundation

/// In-memory navigation history with persistence to UserDefaults.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    struct HistoryEntry: Identifiable, Codable {
        let id: UUID
        let url: String
        let title: String
        let timestamp: Date

        init(url: String, title: String) {
            self.id = UUID()
            self.url = url
            self.title = title
            self.timestamp = Date()
        }
    }

    @Published private(set) var entries: [HistoryEntry] = []
    private let key = "mollotov_history"
    private let maxEntries = 500

    private init() { load() }

    func record(url: String, title: String) {
        // Deduplicate consecutive identical URLs
        if entries.last?.url == url { return }
        entries.append(HistoryEntry(url: url, title: title))
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func toJSON() -> [[String: Any]] {
        entries.reversed().map { e in
            ["id": e.id.uuidString, "url": e.url, "title": e.title,
             "timestamp": ISO8601DateFormatter().string(from: e.timestamp)]
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }
}
