import WebKit
import XCTest
@testable import KelpieBrowser

/// Pages opening new windows: ordinary links become tabs in the root browser
/// store, geometry-bearing opens stay pop-up windows.
@MainActor
final class WebKitNewWindowTests: XCTestCase {
    private var stores: [TabStore] = []

    override func tearDown() async throws {
        for store in stores { store.closeAll() }
        stores = []
    }

    func testBlankTargetLinkOpensSelectedTabInOpenerPartition() async throws {
        let (store, opener, webView) = try await openerPage("""
            <a id="link" href="about:blank" target="_blank">Workspace</a>
            """)

        _ = try await webView.evaluateJavaScript("document.getElementById('link').click()")
        try await waitFor { store.tabs.count == 2 }

        let tab = try XCTUnwrap(store.tabs.last)
        XCTAssertEqual(store.activeTabID, tab.id)
        XCTAssertEqual(tab.partition, opener.partition)
        XCTAssertFalse(tab.persistent)
        XCTAssertFalse(tab.isStartPage)
        XCTAssertTrue(tab.renderer.webView.configuration.websiteDataStore === webView.configuration.websiteDataStore)
        XCTAssertFalse(tab.renderer.webView.configuration.userContentController === webView.configuration.userContentController)
        XCTAssertNil(popupEntry(partition: opener.partition), "A plain link must not open a pop-up window")
    }

    func testWindowOpenWithoutFeaturesKeepsOpenerAndNoopenerDropsIt() async throws {
        let (store, _, webView) = try await openerPage("<p>Opener</p>")

        _ = try await webView.evaluateJavaScript("window.child = window.open('about:blank'); 0")
        try await waitFor { store.tabs.count == 2 }
        let child = try XCTUnwrap(store.tabs.last).renderer.webView
        let hasOpener = try await child.evaluateJavaScript("window.opener !== null") as? Bool
        XCTAssertEqual(hasOpener, true)

        _ = try await webView.evaluateJavaScript("window.isolated = window.open('about:blank', '_blank', 'noopener'); 0")
        try await waitFor { store.tabs.count == 3 }
        let isolated = try XCTUnwrap(store.tabs.last).renderer.webView
        let isolatedOpener = try await isolated.evaluateJavaScript("window.opener === null") as? Bool
        XCTAssertEqual(isolatedOpener, true)
        let handle = try await webView.evaluateJavaScript("window.isolated === null") as? Bool
        XCTAssertEqual(handle, true)
    }

    func testScriptOpenedTabClosesItself() async throws {
        let (store, opener, webView) = try await openerPage("<p>Opener</p>")
        _ = try await webView.evaluateJavaScript("window.child = window.open('about:blank'); 0")
        try await waitFor { store.tabs.count == 2 }

        _ = try await webView.evaluateJavaScript("window.child.close(); 0")
        try await waitFor { store.tabs.count == 1 }
        XCTAssertEqual(store.activeTabID, opener.id)
    }

    func testGeometryOpensPopupAndPopupLinksOpenTabsInRootStore() async throws {
        let (store, opener, webView) = try await openerPage("<p>Opener</p>")

        _ = try await webView.evaluateJavaScript("window.child = window.open('about:blank', 'sign-in', 'width=480,height=640'); 0")
        let entry = try await waitForPopup(partition: opener.partition)
        XCTAssertEqual(store.tabs.count, 1)

        let popupView = try XCTUnwrap(entry.tabStore.activeTab).renderer.webView
        _ = try await popupView.evaluateJavaScript("window.open('about:blank'); 0")
        try await waitFor { store.tabs.count == 2 }
        XCTAssertEqual(entry.tabStore.tabs.count, 1, "The pop-up's own store must not keep the tab")
        let tab = try XCTUnwrap(store.tabs.last)
        XCTAssertEqual(tab.partition, opener.partition)

        _ = try await popupView.evaluateJavaScript("window.close()")
        try await waitFor { WindowRegistry.shared.entry(for: entry.id) == nil }
        XCTAssertEqual(store.tabs.count, 2, "Closing the pop-up must not close the tab it opened")
    }

    func testPlacementAndAppLinkClassification() {
        XCTAssertEqual(WebKitWindowPolicy.placement(hasGeometry: false), .tab)
        XCTAssertEqual(WebKitWindowPolicy.placement(hasGeometry: true), .popup)

        let configuration = WKWebViewConfiguration()
        for link in ["slack://open?team=T1", "zoommtg://zoom.us/join", "mailto:a@example.com", "tel:+4412345"] {
            XCTAssertTrue(WebKitWindowPolicy.opensExternalApp(URL(string: link)!, in: configuration), link)
        }
        for page in ["https://slack.com", "http://localhost:8420", "about:blank", "data:text/plain,hi", "blob:https://a.test/1"] {
            XCTAssertFalse(WebKitWindowPolicy.opensExternalApp(URL(string: page)!, in: configuration), page)
        }
    }

    func testAppLinkAllowanceIsOncePerDocumentWithoutActivation() {
        let allowance = ExternalAppAllowance.of(WKWebView())
        XCTAssertTrue(allowance.permits(userActivated: false))
        XCTAssertFalse(allowance.permits(userActivated: false), "A page must not loop the prompt")
        XCTAssertTrue(allowance.permits(userActivated: true))
        allowance.documentCommitted()
        XCTAssertTrue(allowance.permits(userActivated: false))
    }

    // MARK: - Helpers

    private func openerPage(_ body: String) async throws -> (TabStore, KelpieBrowser.Tab, WKWebView) {
        let partition = "new-window-\(UUID().uuidString.prefix(8))"
        let opener = KelpieBrowser.Tab(spec: TabSpec(partition: partition, persistent: false, dataStore: .nonPersistent()))
        let store = TabStore(isolatedTab: opener)
        stores.append(store)
        let webView = try XCTUnwrap(opener.renderer.makeView() as? WKWebView)
        webView.loadHTMLString("\(body)<script>window.ready = true</script>", baseURL: URL(string: "https://fixture.test"))
        try await waitFor { (try? await webView.evaluateJavaScript("window.ready === true")) as? Bool == true }
        return (store, opener, webView)
    }

    private func popupEntry(partition: String?) -> WindowRegistry.Entry? {
        WindowRegistry.shared.allEntries().first { $0.tabStore.activeTab?.partition == partition }
    }

    private func waitForPopup(partition: String?) async throws -> WindowRegistry.Entry {
        try await waitFor { popupEntry(partition: partition) != nil }
        return try XCTUnwrap(popupEntry(partition: partition))
    }

    private func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<160 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for WebKit")
    }
}
