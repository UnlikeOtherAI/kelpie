import Foundation

/// Persists and restores open tabs across app launches.
///
/// Tabs now carry a display name and an optional storage partition, so the
/// session needs more than a URL list. The record array is written as JSON
/// under a new key; the legacy URL-array key is still read once so an existing
/// install does not lose its tabs on the upgrade, and is cleared afterwards.
enum SessionStore {
    /// One persisted tab.
    struct TabRecord: Codable {
        var url: String
        var name: String?
        var partition: String?
        var persistent = true
        var isActive = false
    }

    private static let tabsKey = "sessionTabs"
    private static let legacyURLsKey = "sessionTabURLs"
    private static let legacyActiveIndexKey = "sessionActiveIndex"

    @MainActor
    static func save(tabs: [Tab], activeID: UUID?) {
        // A non-persistent partition's storage does not survive the process, so
        // restoring its tab would reopen an authenticated-looking tab with an
        // empty store. Drop those at save time; `restore` guards again in case
        // an older blob is still on disk.
        let valid = tabs.filter { !$0.currentURL.isEmpty && !$0.isStartPage && $0.persistent }
        guard !valid.isEmpty else {
            clear()
            return
        }
        let records = valid.map { tab in
            TabRecord(
                url: tab.currentURL,
                name: tab.name,
                partition: tab.partition,
                persistent: tab.persistent,
                isActive: tab.id == activeID
            )
        }
        guard let data = try? JSONEncoder().encode(records) else {
            print("[SessionStore] failed to encode \(records.count) tab record(s) — session not saved")
            return
        }
        UserDefaults.standard.set(data, forKey: tabsKey)
        UserDefaults.standard.removeObject(forKey: legacyURLsKey)
        UserDefaults.standard.removeObject(forKey: legacyActiveIndexKey)
    }

    static func load() -> [TabRecord] {
        if let data = UserDefaults.standard.data(forKey: tabsKey) {
            guard let records = try? JSONDecoder().decode([TabRecord].self, from: data) else {
                print("[SessionStore] tab records failed to decode — starting from a blank session")
                clear()
                return []
            }
            return records
        }
        return loadLegacy()
    }

    /// Reads the pre-partition format: a plain URL array plus an active index.
    private static func loadLegacy() -> [TabRecord] {
        guard let urls = UserDefaults.standard.stringArray(forKey: legacyURLsKey), !urls.isEmpty else {
            return []
        }
        let activeIndex = UserDefaults.standard.integer(forKey: legacyActiveIndexKey)
        return urls.enumerated().map { index, url in
            TabRecord(url: url, isActive: index == activeIndex)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: tabsKey)
        UserDefaults.standard.removeObject(forKey: legacyURLsKey)
        UserDefaults.standard.removeObject(forKey: legacyActiveIndexKey)
    }
}
