import XCTest
@testable import KelpieBrowser

@MainActor
final class BrowserProfileTests: XCTestCase {
    func testRetainedStoresCannotWriteIntoTheNextPersonsProfile() {
        let original = KelpieStorage.profileID
        let first = UUID().uuidString
        let second = UUID().uuidString
        defer { KelpieStorage.select(profile: original) }
        KelpieStorage.select(profile: first)
        let firstDefaults = KelpieStorage.defaults
        let firstHistory = HistoryStore.shared
        let firstBookmarks = BookmarkStore.shared
        let firstWebsiteStore = KelpieWebsiteData.store
        firstHistory.record(url: "https://one.example.test", title: "First person")
        firstBookmarks.add(title: "First person", url: "https://one.example.test")

        KelpieStorage.select(profile: second)
        let secondHistory = HistoryStore.shared
        let secondBookmarks = BookmarkStore.shared
        XCTAssertTrue(secondHistory.entries.isEmpty)
        XCTAssertTrue(secondBookmarks.bookmarks.isEmpty)
        XCTAssertFalse(firstDefaults === KelpieStorage.defaults)
        XCTAssertFalse(firstWebsiteStore === KelpieWebsiteData.store)
        firstHistory.record(url: "https://late.example.test", title: "Late first-person write")
        firstBookmarks.add(title: "Late first-person write", url: "https://late.example.test")
        XCTAssertTrue(secondHistory.entries.isEmpty)
        XCTAssertTrue(secondBookmarks.bookmarks.isEmpty)

        KelpieStorage.select(profile: first)
        XCTAssertEqual(HistoryStore.shared.entries.count, 2)
        XCTAssertEqual(BookmarkStore.shared.bookmarks.count, 2)
        HistoryStore.shared.clear()
        BookmarkStore.shared.removeAll()
    }

    func testAProfileChangeMakesAnOldRouterUnavailable() async {
        let original = KelpieStorage.profileID
        defer { KelpieStorage.select(profile: original) }
        KelpieStorage.select(profile: UUID().uuidString)
        let router = Router()
        var dispatched = false
        router.register("test-only") { _ in dispatched = true; return ["success": true] }
        KelpieStorage.select(profile: UUID().uuidString)
        let result = await router.handle(method: "test-only", body: [:])
        XCTAssertEqual(result.statusCode, 410)
        XCTAssertFalse(dispatched)
    }
}
