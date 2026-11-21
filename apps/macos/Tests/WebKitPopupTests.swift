import WebKit
import XCTest
@testable import KelpieBrowser

@MainActor
final class WebKitPopupTests: XCTestCase {
    func testPopupKeepsOpenerAndPartitionAndCanSendResultBeforeClosing() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let opener = Tab(spec: TabSpec(partition: "popup-test", persistent: false, dataStore: dataStore))
        let store = TabStore(isolatedTab: opener)
        defer { store.closeAll() }
        let webView = try XCTUnwrap(opener.renderer.makeView() as? WKWebView)
        webView.loadHTMLString("""
            <button id="open">Continue</button>
            <script>
                window.result = '';
                document.querySelector('#open').onclick = () => window.postMessage('open', '*');
                window.addEventListener('message', event => {
                    if (event.data === 'open') window.child = window.open('about:blank', 'sign-in');
                    else window.result = event.data;
                });
            </script>
            """, baseURL: URL(string: "https://fixture.test"))
        try await waitFor { (try? await webView.evaluateJavaScript("window.result")) as? String == "" }
        XCTAssertEqual(store.tabs.count, 1)

        _ = try await webView.evaluateJavaScript("document.getElementById('open').click()")
        try await waitFor { (try? await webView.evaluateJavaScript("!!window.child")) as? Bool == true }
        let entry = try XCTUnwrap(WindowRegistry.shared.allEntries().first {
            $0.tabStore.activeTab?.partition == opener.partition
        }, "The click should open a separate window")
        XCTAssertTrue(entry.window?.isVisible == true)
        XCTAssertNil(webView.window)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.activeTabID, opener.id)
        let popup = try XCTUnwrap(entry.tabStore.activeTab)
        XCTAssertEqual(popup.partition, opener.partition)
        XCTAssertFalse(popup.persistent)
        XCTAssertFalse(popup.isStartPage)
        let popupView = try XCTUnwrap(popup.renderer.makeView() as? WKWebView)
        XCTAssertTrue(popupView.configuration.websiteDataStore === dataStore)
        XCTAssertFalse(popupView.configuration.userContentController === webView.configuration.userContentController)
        let openerKnowsPopup = try await webView.evaluateJavaScript("!!window.child && !window.child.closed") as? Bool
        XCTAssertEqual(openerKnowsPopup, true)

        _ = try await popupView.evaluateJavaScript("window.opener.postMessage('signed-in', '*'); window.close();")
        try await waitFor { WindowRegistry.shared.entry(for: entry.id) == nil }
        try await waitFor { (try? await webView.evaluateJavaScript("window.result")) as? String == "signed-in" }
        XCTAssertEqual(store.tabs.count, 1)
    }

    private func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for WebKit")
    }
}
