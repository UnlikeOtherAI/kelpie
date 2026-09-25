import AppKit
import XCTest
@testable import Kelpie

final class BookmarkChromeTests: XCTestCase {
    func testSavedPagesPersistWithoutDuplicatesAndRemovingLastHidesRow() throws {
        let suite = "BookmarkChromeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BookmarkStore(defaults: defaults)
        XCTAssertTrue(store.bookmarks.isEmpty)
        XCTAssertEqual(BrowserChromeLayout.underlap(collapsed: false, hasBookmarks: false), 76)
        XCTAssertTrue(store.addPage(title: "Example", url: "https://example.org/", isStartPage: false))
        XCTAssertFalse(store.addPage(title: "Duplicate", url: "https://example.org/", isStartPage: false))
        let restored = BookmarkStore(defaults: defaults)
        XCTAssertEqual(restored.bookmarks, store.bookmarks)
        XCTAssertEqual(restored.bookmarks.count, 1)
        XCTAssertEqual(BrowserChromeLayout.underlap(collapsed: false, hasBookmarks: !restored.bookmarks.isEmpty), 105)
        restored.remove(id: try XCTUnwrap(restored.bookmarks.first).id)
        XCTAssertTrue(BookmarkStore(defaults: defaults).bookmarks.isEmpty)
        XCTAssertEqual(BrowserChromeLayout.underlap(collapsed: true, hasBookmarks: true), 32)
        XCTAssertEqual(BrowserChromeLayout.underlap(collapsed: true, hasBookmarks: false), 32)
    }

    func testBookmarkActionsRejectStartPagesAndInvalidURLs() throws {
        let suite = "BookmarkChromeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BookmarkStore(defaults: defaults)
        for url in ["", "about:blank", "kelpie://start", "file:///tmp/page.html", "https://", "relative"] {
            XCTAssertFalse(store.addPage(title: "", url: url, isStartPage: false))
        }
        XCTAssertFalse(store.addPage(title: "", url: "https://example.org/", isStartPage: true))
        XCTAssertTrue(store.bookmarks.isEmpty)
        XCTAssertTrue(store.addPage(title: "", url: "https://example.org/", isStartPage: false))
        XCTAssertEqual(store.bookmarks.first?.title, "https://example.org/")
    }

    @MainActor
    func testBookmarkShortcutOnlyTargetsActiveWindow() {
        let router = BrowserCommandRouter.shared
        let first = NSWindow(), second = NSWindow()
        var firstCount = 0, secondCount = 0
        let firstActions = BrowserCommandActions(hardReload: {}, newTab: {}, closeTab: {}, addBookmark: { firstCount += 1 })
        let secondActions = BrowserCommandActions(hardReload: {}, newTab: {}, closeTab: {}, addBookmark: { secondCount += 1 })
        router.activate(window: first, actions: firstActions)
        router.activate(window: second, actions: secondActions)
        router.update(window: first, actions: firstActions)
        router.deactivate(window: first)
        router.addBookmark()
        XCTAssertEqual(firstCount, 0)
        XCTAssertEqual(secondCount, 1)
        router.deactivate(window: second)
        router.addBookmark()
        XCTAssertEqual(secondCount, 1)
    }
}
