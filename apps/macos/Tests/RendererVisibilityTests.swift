import AppKit
import WebKit
import XCTest
@testable import KelpieBrowser

@MainActor
final class RendererVisibilityTests: XCTestCase {
    func testScreenshotRefusesHiddenSelectedTabAndRecoversWhenShown() async throws {
        let tab = KelpieBrowser.Tab(spec: TabSpec(persistent: false, dataStore: .nonPersistent()))
        let store = TabStore(isolatedTab: tab)
        let renderer = tab.renderer
        let webView = try XCTUnwrap(renderer.makeView() as? WKWebView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let windowId = UUID().uuidString
        let target = ["tabId": tab.id.uuidString]
        let context = HandlerContext()
        let router = Router()
        ScreenshotHandler(context: context).register(on: router)
        BrowserManagementHandler(context: context, viewportState: ViewportState()).register(on: router)
        window.contentView = webView
        window.level = .floating
        window.orderFrontRegardless()
        WindowRegistry.shared.register(id: windowId, window: window, tabStore: store)
        defer {
            WindowRegistry.shared.unregister(id: windowId)
            window.orderOut(nil)
            window.contentView = nil
        }

        webView.loadHTMLString("<!doctype html><title>Renderer visibility fixture</title>", baseURL: nil)
        try await waitForDocument("visible", in: renderer)
        let first = await router.handle(method: "screenshot", body: target).json
        XCTAssertEqual(first["success"] as? Bool, true)
        XCTAssertNotNil(first["image"])

        window.orderOut(nil)
        try await waitForDocument("hidden", in: renderer)
        let listing = await router.handle(method: "get-tabs", body: ["windowId": windowId]).json
        XCTAssertEqual(listing["activeTab"] as? String, tab.id.uuidString)
        let hidden = await router.handle(method: "screenshot", body: target).json
        XCTAssertEqual(hidden["success"] as? Bool, false)
        XCTAssertEqual((hidden["error"] as? [String: Any])?["code"] as? String, "RENDERER_HIDDEN")
        XCTAssertNil(hidden["image"])

        window.orderFrontRegardless()
        try await waitForDocument("visible", in: renderer)
        let recovered = await router.handle(method: "screenshot", body: target).json
        XCTAssertEqual(recovered["success"] as? Bool, true)
        XCTAssertNotNil(recovered["image"])
    }

    private func waitForDocument(_ visibility: String, in renderer: WKWebViewRenderer) async throws {
        for _ in 0..<100 {
            let state = try? await renderer.evaluateJS(
                "document.title === 'Renderer visibility fixture' && document.visibilityState"
            ) as? String
            if state == visibility { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("The fixture document did not become \(visibility)")
    }
}
