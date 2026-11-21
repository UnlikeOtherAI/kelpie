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
        let coordinator = TabWebViewContainer.Coordinator(
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
                if (event.data === 'open') window.child = window.open('about:blank', 'sign-in');
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
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for the pop-up flow")
    }
}
