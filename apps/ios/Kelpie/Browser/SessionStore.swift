import Foundation

/// Persists and restores the set of open tab URLs across app launches.
enum SessionStore {
    private static let urlsKey = "sessionTabURLs"
    private static let activeIndexKey = "sessionActiveIndex"

    @MainActor
    static func save(tabs: [BrowserTab], activeID: UUID?) {
        let valid = tabs.filter { !$0.currentURL.isEmpty && !$0.isStartPage }
        guard !valid.isEmpty else {
            clear()
            return
        }
        let urls = valid.map { $0.currentURL }
        let activeIndex = valid.firstIndex(where: { $0.id == activeID }) ?? 0
        UserDefaults.standard.set(urls, forKey: urlsKey)
        UserDefaults.standard.set(activeIndex, forKey: activeIndexKey)
    }

    static func load() -> (urls: [String], activeIndex: Int)? {
        guard let urls = UserDefaults.standard.stringArray(forKey: urlsKey),
              !urls.isEmpty else { return nil }
        let activeIndex = UserDefaults.standard.integer(forKey: activeIndexKey)
        return (urls, activeIndex)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: urlsKey)
        UserDefaults.standard.removeObject(forKey: activeIndexKey)
    }
}
