import WebKit
import XCTest
@testable import Kelpie

@MainActor
final class MobileSessionStorageTests: XCTestCase {
    func testNativeLoginCookiesShareOrdinaryTabsButNotNamedPartitions() async throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Named stores require iOS 17") }
        let suite = "mobile-partitions-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let registry = MobilePartitionRegistry(defaults: defaults)
        let login = UOALoginWebController(dataStore: WebViewDefaults.sharedWebsiteDataStore, userAgent: WebViewDefaults.sharedUserAgent)
        let ordinary = WKWebView()
        let named = try registry.resolve("first")
        let sibling = try registry.resolve("first")
        let other = try registry.resolve("second")
        XCTAssertTrue(named === sibling)
        XCTAssertFalse(named === other)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .name: suite, .value: "session", .domain: "fixture.invalid", .path: "/", .secure: "TRUE",
            HTTPCookiePropertyKey("HttpOnly"): "TRUE", .expires: Date().addingTimeInterval(3600)
        ]))
        let sharedCookies = login.webView.configuration.websiteDataStore.httpCookieStore
        await sharedCookies.setCookie(cookie)
        login.stop()
        let ordinaryCookies = await ordinary.configuration.websiteDataStore.httpCookieStore.allCookies()
        let isolatedCookies = await named.httpCookieStore.allCookies()
        XCTAssertEqual(ordinaryCookies.first { $0.name == suite }?.value, "session")
        XCTAssertNil(isolatedCookies.first { $0.name == suite })
        await named.httpCookieStore.setCookie(cookie)
        let siblingCookies = await sibling.httpCookieStore.allCookies()
        let otherCookies = await other.httpCookieStore.allCookies()
        XCTAssertEqual(siblingCookies.first { $0.name == suite }?.value, "session")
        XCTAssertNil(otherCookies.first { $0.name == suite })
        let restored = MobilePartitionRegistry(defaults: defaults)
        let rebound = try restored.resolve("first", restoring: true)
        XCTAssertEqual(rebound.identifier, named.identifier)
        XCTAssertThrowsError(try restored.resolve("missing", restoring: true))
        await sharedCookies.deleteCookie(cookie)
        await named.httpCookieStore.deleteCookie(cookie)
        for store in [named, other] {
            if let identifier = store.identifier {
                await withCheckedContinuation { continuation in
                    WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in continuation.resume() }
                }
            }
        }
    }

    func testIsolationRequestsCannotSilentlyCreateSharedTabs() async throws {
        let context = HandlerContext()
        let initial = BrowserTab(webView: WKWebView(), recordsHistory: false)
        let tabs = TabStore(isolatedTab: initial)
        context.tabStore = tabs
        let router = Router()
        MobileTabHandler(context: context).register(on: router)
        for body: [String: Any] in [
            ["partition": "../escape"], ["partition": "default"], ["partition": 42],
            ["partition": "private", "persistent": false], ["partition": "private", "persistent": "false"]
        ] {
            let response = await router.handle(method: "new-tab", body: body)
            XCTAssertEqual(response.json["success"] as? Bool, false)
            XCTAssertEqual(tabs.tabs.count, 1)
        }
        let response = await router.handle(method: "new-tab", body: [:])
        XCTAssertEqual(response.json["success"] as? Bool, true)
        XCTAssertTrue(tabs.activeBrowserTab?.webView.configuration.websiteDataStore === WebViewDefaults.sharedWebsiteDataStore)
    }

    func testDeselectingNetworkEntryClearsTheNativeSelection() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NetworkTrafficStore(persistence: NetworkTrafficPersistence(fileURL: directory.appendingPathComponent("traffic.json"), interval: 3600))
        store.appendDocumentNavigation(url: "https://fixture.invalid", statusCode: 200, contentType: "text/html", startedAt: Date())
        store.selectedIndex = 0
        XCTAssertNotNil(store.selectedEntry)
        store.selectedIndex = nil
        store.appendDocumentNavigation(url: "https://fixture.invalid/next", statusCode: 200, contentType: "text/html", startedAt: Date())
        XCTAssertNil(store.selectedEntry)
    }

    func testUnknownOrphanDeletionDoesNotReachWebKit() async throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Named stores require iOS 17") }
        let initial = BrowserTab(webView: WKWebView(), recordsHistory: false)
        let tabs = TabStore(isolatedTab: initial)
        let registry = MobilePartitionRegistry()
        for id in ["orphan:00000000-0000-0000-0000-000000000000", "orphan:\(UUID().uuidString)"] {
            let result = await registry.delete(id, tabStore: tabs)
            XCTAssertEqual(result["success"] as? Bool, true)
            XCTAssertEqual(result["existed"] as? Bool, false)
            XCTAssertEqual(tabs.tabs.count, 1)
        }
    }
}
