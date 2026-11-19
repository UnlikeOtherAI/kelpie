import UIKit
import WebKit
import XCTest
@testable import KelpieBrowser

@MainActor
final class RealWebKitScrollTests: XCTestCase {
    func testCanonicalDeltaAndNativePageEdgesMoveTheRenderer() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 600), configuration: configuration)
        let context = HandlerContext()
        context.webView = webView
        let router = Router()
        router.handlerContext = context
        ScrollHandler(context: context).register(on: router)
        let tabId = "external"
        router.register("get-tabs") { _ in
            successResponse(["tabs": [["id": tabId, "active": true, "url": "https://fixture.test"]]])
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view.addSubview(webView)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        webView.loadHTMLString(
            "<!doctype html><meta name='viewport' content='width=device-width'><body style='min-height:20000px'>Scroll</body>",
            baseURL: URL(string: "https://fixture.test")
        )
        for _ in 0..<100 {
            let height = try? await webView.evaluateJavaScript("document.documentElement.scrollHeight")
            if !webView.isLoading, (height as? Double ?? 0) >= 20_000 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        try await assertScroll(12_000, landsAt: 12_000, router: router, webView: webView, tabId: tabId)
        try await assertScroll(-200, landsAt: 11_800, router: router, webView: webView, tabId: tabId)
        let invalid = await router.browserControl([
            "version": 1, "method": "page.scroll", "tabId": tabId, "params": ["deltaY": 100_001]
        ])
        XCTAssertEqual((invalid["error"] as? [String: Any])?["code"] as? String, "INVALID_ARGUMENTS")

        let (_, top) = await router.handle(method: "scroll-to-top", body: [:])
        XCTAssertEqual(top["scrollY"] as? Double, 0)
        let (_, bottom) = await router.handle(method: "scroll-to-bottom", body: [:])
        XCTAssertGreaterThan(try XCTUnwrap(bottom["scrollY"] as? Double), 12_000)
    }

    private func assertScroll(
        _ delta: Int, landsAt expected: Double, router: Router, webView: WKWebView, tabId: String
    ) async throws {
        let response = await router.browserControl([
            "version": 1, "method": "page.scroll", "tabId": tabId, "params": ["deltaY": delta]
        ])
        XCTAssertEqual(response["ok"] as? Bool, true)
        let offset = try await webView.evaluateJavaScript("window.scrollY")
        XCTAssertEqual(try XCTUnwrap(offset as? Double), expected, accuracy: 1)
    }
}
