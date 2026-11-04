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

    func testLegacyRequestUsesSelectedStoreBeforeSwiftUIRebinds() async throws {
        let ordinary = WKWebView()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let isolated = WKWebView(frame: .zero, configuration: config)
        let context = HandlerContext()
        context.webView = ordinary
        context.tabStore = TabStore(isolatedTab: BrowserTab(webView: isolated, recordsHistory: false))
        let router = Router()
        router.handlerContext = context
        BrowserManagementHandler(context: context).register(on: router)
        let name = "routing-\(UUID().uuidString)"
        let result = await router.handle(method: "set-cookie", body: [
            "name": name, "value": "isolated", "domain": "fixture.invalid", "path": "/"
        ])
        XCTAssertEqual(result.json["success"] as? Bool, true)
        let isolatedCookies = await isolated.configuration.websiteDataStore.httpCookieStore.allCookies()
        let ordinaryCookies = await ordinary.configuration.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertEqual(isolatedCookies.first { $0.name == name }?.value, "isolated")
        XCTAssertNil(ordinaryCookies.first { $0.name == name })
        for cookie in ordinaryCookies where cookie.name == name {
            await ordinary.configuration.websiteDataStore.httpCookieStore.deleteCookie(cookie)
        }
    }

    func testSuspendedLegacyRequestKeepsItsViewWithoutRebindingOtherContexts() async {
        let selected = WKWebView()
        let visible = WKWebView()
        let context = HandlerContext()
        context.webView = visible
        context.tabStore = TabStore(isolatedTab: BrowserTab(webView: selected, recordsHistory: false))
        let otherContext = HandlerContext()
        otherContext.webView = visible
        let router = Router()
        router.handlerContext = context
        router.register("fixture-target") { _ in
            XCTAssertTrue(context.webView === selected)
            context.webView = visible
            await Task.yield()
            XCTAssertTrue(context.webView === selected)
            XCTAssertTrue(otherContext.webView === visible)
            return successResponse()
        }
        _ = await router.handle(method: "fixture-target", body: [:])
        XCTAssertTrue(context.webView === visible)
        context.tabStore?.activeBrowserTabID = nil
        let missing = await router.handle(method: "fixture-target", body: [:])
        XCTAssertEqual((missing.json["error"] as? [String: Any])?["code"] as? String, "NO_WEBVIEW")
    }

    func testLegacyBindingPreservesPinnedAndExternalDisplayContexts() async {
        let pinned = WKWebView()
        let selected = WKWebView()
        let context = HandlerContext()
        context.webView = pinned
        context.tabStore = TabStore(isolatedTab: BrowserTab(webView: selected, recordsHistory: false))
        let router = Router()
        router.handlerContext = context
        router.register("fixture-target") { _ in
            XCTAssertTrue(context.webView === pinned)
            return successResponse()
        }
        context.remoteDocumentGuard = { true }
        _ = await router.handle(method: "fixture-target", body: [:])
        context.remoteDocumentGuard = nil
        _ = await router.handle(method: "fixture-target", body: [:], browserGatewayDispatch: true)
        context.tabStore = nil
        _ = await router.handle(method: "fixture-target", body: [:])
    }

    func testInheritedTaskLocalsDoNotKeepRetiredWebViewsAlive() async {
        let context = HandlerContext()
        var view: WKWebView? = WKWebView()
        let (events, continuation) = AsyncStream<Void>.makeStream()
        var child: Task<Bool, Never>?
        await context.withBrowserTarget(view!) {
            child = Task {
                for await _ in events { return context.webView == nil }
                return false
            }
        }
        view = nil
        continuation.yield(())
        continuation.finish()
        let released = await child?.value
        XCTAssertEqual(released, true)
    }

    func testUnavailableRestoredPageKeepsItsSavedDestination() async throws {
        let view = WKWebView()
        let tab = BrowserTab(webView: view, isStartPage: false, recordsHistory: false, partition: "offline")
        let destination = "http://127.0.0.1:18529/unavailable"
        tab.currentURL = destination
        let failure = expectation(description: "Provisional load failed")
        let delegate = FailedNavigationObserver(failure: failure)
        view.navigationDelegate = delegate
        view.load(URLRequest(url: try XCTUnwrap(URL(string: destination)), timeoutInterval: 2))
        await fulfillment(of: [failure], timeout: 5)
        await Task.yield()
        XCTAssertEqual(tab.currentURL, destination)
        XCTAssertEqual(tab.partition, "offline")
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

private final class FailedNavigationObserver: NSObject, WKNavigationDelegate {
    let failure: XCTestExpectation
    init(failure: XCTestExpectation) { self.failure = failure }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failure.fulfill()
    }
}
