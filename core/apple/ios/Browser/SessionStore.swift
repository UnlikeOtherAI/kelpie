import Foundation

/// Versioned tab identity. Downgrades see only ordinary URLs in the legacy keys.
enum SessionStore {
    struct TabRecord: Codable {
        let url: String
        let partition: String?
        let name: String?
    }
    struct Snapshot: Codable {
        let version: Int
        let tabs: [TabRecord]
        let activeIndex: Int
    }
    private static let key = "sessionTabsV2"
    private static let urlsKey = "sessionTabURLs"
    private static let activeIndexKey = "sessionActiveIndex"

    @MainActor
    static func save(tabs: [BrowserTab], activeID: UUID?) {
        let valid = tabs.filter { !$0.currentURL.isEmpty && !$0.isStartPage }
        let records = valid.map { TabRecord(url: $0.currentURL, partition: $0.partition, name: $0.name) }
        let snapshot = Snapshot(version: 2, tabs: records, activeIndex: valid.firstIndex(where: { $0.id == activeID }) ?? 0)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        KelpieStorage.defaults.set(data, forKey: key)
        // An older app must never reopen an isolated URL in its default profile.
        KelpieStorage.defaults.set(valid.filter { $0.partition == nil }.map(\.currentURL), forKey: urlsKey)
        KelpieStorage.defaults.set(0, forKey: activeIndexKey)
    }

    static func load() -> Snapshot? {
        if let data = KelpieStorage.defaults.data(forKey: key) {
            guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data), snapshot.version == 2 else { return nil }
            return snapshot
        }
        guard let urls = KelpieStorage.defaults.stringArray(forKey: urlsKey), !urls.isEmpty else { return nil }
        return Snapshot(
            version: 2,
            tabs: urls.map { TabRecord(url: $0, partition: nil, name: nil) },
            activeIndex: max(0, KelpieStorage.defaults.integer(forKey: activeIndexKey))
        )
    }

    static func clear() {
        for key in [key, urlsKey, activeIndexKey] { KelpieStorage.defaults.removeObject(forKey: key) }
    }
}
