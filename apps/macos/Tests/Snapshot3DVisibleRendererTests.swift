import AppKit
import WebKit
import XCTest
@testable import KelpieBrowser

@MainActor
final class Snapshot3DVisibleRendererTests: XCTestCase {
    func testInspectorAndPreviewFollowTheDisplayedRenderer() async throws {
        let hiddenTab = Tab(spec: TabSpec(persistent: false, dataStore: .nonPersistent()))
        let store = TabStore(isolatedTab: hiddenTab)
        let visible = WKWebViewRenderer(dataStore: .nonPersistent())
        let webView = try XCTUnwrap(visible.makeView() as? WKWebView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        let windowID = UUID().uuidString
        WindowRegistry.shared.register(id: windowID, window: window, tabStore: store)
        defer {
            WindowRegistry.shared.unregister(id: windowID)
            window.orderOut(nil)
            visible.invalidate()
            hiddenTab.renderer.invalidate()
        }
        webView.loadHTMLString("<main><h1 id='fixture'>Visible page</h1><footer>Footer</footer></main>", baseURL: nil)
        for _ in 0..<100 {
            if !webView.isLoading,
               (try? await webView.evaluateJavaScript("!!document.getElementById('fixture')")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let context = HandlerContext()
        context.renderer = visible
        try await context.enter3DInspector(windowId: windowID)
        let active = try await visible.evaluateJS("!!window.__m3d")
        XCTAssertEqual(active as? Bool, true)
        let hiddenActive = try await hiddenTab.renderer.evaluateJS("!!window.__m3d")
        XCTAssertEqual(hiddenActive as? Bool, false)
        let controls = "document.getElementById('__m3d_overlay').lastElementChild.shadowRoot"
        for _ in 0..<100 {
            if (try? await visible.evaluateJS("\(controls).querySelector('img').naturalWidth > 0")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let preview = try await visible.evaluateJS("\(controls).querySelector('img').naturalWidth > 0")
        XCTAssertEqual(preview as? Bool, true, "Orientation card must contain a native page snapshot")
        _ = try await context.evaluate3DInspectorJS(Snapshot3DBridge.setModeScript("pan"), windowId: windowID)
        let mode = try await visible.evaluateJS("window.__m3d.getMode()")
        XCTAssertEqual(mode as? String, "pan")
        context.remoteDocumentGuard = { false }
        do {
            _ = try await context.evaluate3DInspectorJS("window.__m3d.resetView()", windowId: windowID)
            XCTFail("Revoked document authority must refuse inspector control")
        } catch is CancellationError {
            // Expected: the inspector keeps the same remote document guard.
        }
        context.remoteDocumentGuard = nil
        _ = try await context.evaluate3DInspectorJS(Snapshot3DBridge.exitScript, windowId: windowID)
        let restored = try await visible.evaluateJS("!window.__m3d && !document.getElementById('__m3d_overlay')")
        XCTAssertEqual(restored as? Bool, true)
    }
}
