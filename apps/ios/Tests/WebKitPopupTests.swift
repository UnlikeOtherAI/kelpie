import UIKit
import WebKit
import XCTest
@testable import KelpieBrowser

@MainActor
final class WebKitPopupTests: XCTestCase {
    func testSignInHandoffPresentsNewContextAndReturnsResult() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.websiteDataStore = .nonPersistent()
        let opener = WKWebView(frame: .zero, configuration: configuration)
        let store = TabStore(isolatedTab: BrowserTab(webView: opener, isStartPage: false, recordsHistory: false))
        let coordinator = TabWebViewContainer.Coordinator(
            tabStore: store,
            browserState: BrowserState(),
            handlerContext: nil,
            onScrollDirectionChange: { _ in },
            onWebViewReady: { _ in }
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        coordinator.install(webView: opener, in: root.view)
        defer { window.isHidden = true }

        opener.loadHTMLString("""
            <title>Original page</title>
            <button onclick="window.postMessage('open', '*')">Sign in</button>
            <script>
            window.addEventListener('message', event => {
                if (event.data === 'open') window.child = window.open('about:blank', 'sign-in', 'width=480,height=640');
                else document.title = event.data;
            });
            </script>
            """, baseURL: URL(string: "https://fixture.test"))
        try await waitFor { opener.title == "Original page" }
        _ = try await opener.evaluateJavaScript("document.querySelector('button').click()")
        try await waitFor { root.presentedViewController != nil }

        let navigation = try XCTUnwrap(root.presentedViewController as? UINavigationController)
        let popup = try XCTUnwrap(navigation.topViewController as? WKPopupViewController)
        XCTAssertEqual(opener.title, "Original page")
        XCTAssertTrue(popup.webView.configuration.websiteDataStore === configuration.websiteDataStore)
        let connected = try await opener.evaluateJavaScript("!!window.child && !window.child.closed") as? Bool
        XCTAssertEqual(connected, true)
        _ = try await popup.webView.evaluateJavaScript("window.opener.postMessage('Signed in', '*'); window.close();")
        try await waitFor { root.presentedViewController == nil && opener.title == "Signed in" }
        XCTAssertEqual(store.tabs.count, 1)
    }

    func testNewWindowLinksOpenSelectedTabsAndKeepTheEngineOpener() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.websiteDataStore = .nonPersistent()
        let opener = WKWebView(frame: .zero, configuration: configuration)
        let store = TabStore(isolatedTab: BrowserTab(webView: opener, isStartPage: false, recordsHistory: false, partition: "work"))
        let coordinator = TabWebViewContainer.Coordinator(
            tabStore: store,
            browserState: BrowserState(),
            handlerContext: nil,
            onScrollDirectionChange: { _ in },
            onWebViewReady: { _ in }
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        coordinator.install(webView: opener, in: root.view)
        defer { window.isHidden = true }

        opener.loadHTMLString("""
            <title>Workspaces</title>
            <a id="link" href="about:blank" target="_blank">Workspace</a>
            """, baseURL: URL(string: "https://fixture.test"))
        try await waitFor { opener.title == "Workspaces" }

        _ = try await opener.evaluateJavaScript("document.getElementById('link').click()")
        try await waitFor { store.tabs.count == 2 }
        let linked = try XCTUnwrap(store.tabs.last)
        XCTAssertEqual(store.activeBrowserTabID, linked.id)
        XCTAssertEqual(linked.partition, "work")
        XCTAssertFalse(linked.isStartPage)
        XCTAssertNil(root.presentedViewController, "A plain link must not present a pop-up")
        XCTAssertTrue(linked.webView.configuration.websiteDataStore === configuration.websiteDataStore)

        _ = try await opener.evaluateJavaScript("window.child = window.open('about:blank'); 0")
        try await waitFor { store.tabs.count == 3 }
        let child = try XCTUnwrap(store.tabs.last).webView
        let hasOpener = try await child.evaluateJavaScript("window.opener !== null") as? Bool
        XCTAssertEqual(hasOpener, true)

        _ = try await opener.evaluateJavaScript("window.child.close(); 0")
        try await waitFor { store.tabs.count == 2 }
    }

    func testAppLinkAsksOnceWithoutActivation() {
        XCTAssertTrue(WebKitWindowPolicy.opensExternalApp(URL(string: "slack://open")!, in: WKWebViewConfiguration()))
        XCTAssertFalse(WebKitWindowPolicy.opensExternalApp(URL(string: "https://slack.com")!, in: WKWebViewConfiguration()))
        ExternalAppAllowance.lastUserInput = nil
        let allowance = ExternalAppAllowance.of(WKWebView())
        XCTAssertTrue(allowance.permits(userActivated: false))
        XCTAssertFalse(allowance.permits(userActivated: false))
        XCTAssertTrue(allowance.permits(userActivated: true))
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for the pop-up flow")
    }
}
