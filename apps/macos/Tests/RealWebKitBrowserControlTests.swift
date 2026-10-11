import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import XCTest
@testable import Kelpie

@MainActor
final class RealWebKitBrowserControlTests: XCTestCase {
    func testIsolatedProductionBindingUsesPrivateRefsAtomicActionsAndOneScreenshot() async throws {
        let context = HandlerContext()
        let router = Router()
        router.handlerContext = context
        let webView: WKWebView
        let tabId: String
        #if os(macOS)
        let tab = Tab(spec: TabSpec(persistent: false, dataStore: .nonPersistent()))
        let renderer = tab.renderer
        let store = TabStore(isolatedTab: tab)
        context.renderer = renderer
        webView = try XCTUnwrap(renderer.makeView() as? WKWebView)
        let windowId = UUID().uuidString
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        WindowRegistry.shared.register(id: windowId, window: window, tabStore: store)
        tabId = tab.id.uuidString
        defer {
            WindowRegistry.shared.unregister(id: windowId)
            window.orderOut(nil)
            renderer.invalidate()
        }
        #else
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        context.webView = webView
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        let controller = UIViewController()
        controller.view.addSubview(webView)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        tabId = "external"
        defer { window.isHidden = true }
        #endif
        InteractionHandler(context: context).register(on: router)
        ScreenshotHandler(context: context).register(on: router)
        router.register("get-tabs") { _ in successResponse(["tabs": [["id": tabId, "active": true, "title": "Isolated fixture", "url": "https://fixture.test"]]]) }
        webView.loadHTMLString(Self.fixture, baseURL: URL(string: "https://fixture.test"))
        for _ in 0..<100 {
            if !webView.isLoading, (try? await webView.evaluateJavaScript("!!document.getElementById('entry')")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(webView.isLoading, "Fixture navigation must settle before observation")
        let observed = try await snapshot(router, tabId: tabId)
        for secret in ["editable-secret", "textarea-secret", "password-secret", "seed-"] {
            XCTAssertFalse(BrowserControlGateway.encode(observed).contains(secret))
        }
        let elements = try XCTUnwrap(observed["elements"] as? [[String: Any]])
        let button = try XCTUnwrap(elements.first { $0["name"] as? String == "Activate" }?["ref"] as? String)
        let activated = await router.browserControl(["version": 1, "method": "tab.click", "tabId": tabId, "params": ["ref": button]])
        XCTAssertEqual(activated["ok"] as? Bool, true)
        let count = try await webView.evaluateJavaScript("window.activations")
        XCTAssertEqual(count as? Int, 1, "Page-world prototype spoof cannot replace private activation")
        let fresh = try await snapshot(router, tabId: tabId)
        let fields = try XCTUnwrap(fresh["elements"] as? [[String: Any]])
        let entry = try XCTUnwrap(fields.first { $0["name"] as? String == "Entry" }?["ref"] as? String)
        let typed = await router.browserControl(["version": 1, "method": "tab.type", "tabId": tabId, "params": ["ref": entry, "text": "tail"]])
        XCTAssertEqual(typed["ok"] as? Bool, true)
        let text = try await webView.evaluateJavaScript("document.getElementById('entry').value")
        XCTAssertEqual(text as? String, "seed-tail")
        let beforeReplacement = try await snapshot(router, tabId: tabId)
        let references = try XCTUnwrap(beforeReplacement["elements"] as? [[String: Any]])
        let oldButton = try XCTUnwrap(references.first { $0["name"] as? String == "Activate" }?["ref"] as? String)
        // The page replaces its own DOM without a router mutation/invalidation.
        _ = try await webView.evaluateJavaScript("const old = document.getElementById('activate'); old.replaceWith(old.cloneNode(true))")
        let stale = await router.browserControl(["version": 1, "method": "tab.click", "tabId": tabId, "params": ["ref": oldButton]])
        XCTAssertEqual((stale["error"] as? [String: Any])?["code"] as? String, "STALE_REFERENCE")
        XCTAssertEqual((stale["error"] as? [String: Any])?["mayHaveCompleted"] as? Bool, false)
        let captured = await router.browserMCP([
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "kelpie_browser_control", "arguments": [
                "request": ["version": 1, "method": "tab.screenshot", "tabId": tabId, "params": [:]]
            ]]
        ])
        let result = try XCTUnwrap(captured["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let images = content.filter { $0["type"] as? String == "image" }
        XCTAssertEqual(images.count, 1)
        let encoded = try XCTUnwrap(images.first?["data"] as? String)
        XCTAssertNotNil(Data(base64Encoded: encoded))
        XCTAssertFalse(content.filter { $0["type"] as? String == "text" }.contains { ($0["text"] as? String)?.contains(encoded) == true })

        let delayed = try await snapshot(router, tabId: tabId)
        let delayedElements = try XCTUnwrap(delayed["elements"] as? [[String: Any]])
        let delayedRef = try XCTUnwrap(delayedElements.first { $0["name"] as? String == "Delayed" }?["ref"] as? String)
        let action = Task { await router.browserControl(["version": 1, "method": "tab.click", "tabId": tabId, "params": ["ref": delayedRef]]) }
        try await Task.sleep(nanoseconds: 100_000_000)
        action.cancel()
        let uncertain = await action.value
        XCTAssertEqual((uncertain["error"] as? [String: Any])?["mayHaveCompleted"] as? Bool, true)
        // Exceed the former inner WK 8s deadline while the actual callback remains pending.
        try await Task.sleep(nanoseconds: 8_300_000_000)
        let premature = router.browserLease.begin()
        if premature { router.browserLease.end() }
        XCTAssertFalse(premature, "A cancelled response cannot retire a running renderer gesture")
        for _ in 0..<100 {
            if router.browserLease.begin() { router.browserLease.end(); break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let recovered = router.browserLease.begin()
        if recovered { router.browserLease.end() }
        XCTAssertTrue(recovered, "The actual late callback releases the lease without restarting")
        let delayedActivations = try await webView.evaluateJavaScript("window.delayedActivations")
        XCTAssertEqual(delayedActivations as? Int, 1)
    }

    #if os(macOS)
    func testAgentReadDiscardsOutputWhenPinnedWindowLosesSelection() async {
        let tab = Tab(spec: TabSpec(persistent: false, dataStore: .nonPersistent()))
        let store = TabStore(isolatedTab: tab)
        let windowId = UUID().uuidString
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.makeKeyAndOrderFront(nil)
        WindowRegistry.shared.register(id: windowId, window: window, tabStore: store)
        defer {
            WindowRegistry.shared.unregister(id: windowId)
            window.orderOut(nil)
            tab.renderer.invalidate()
        }
        let context = HandlerContext()
        context.renderer = tab.renderer
        let router = Router()
        router.handlerContext = context
        var pending: CheckedContinuation<[String: Any], Never>?
        router.register("get-tabs") { _ in await withCheckedContinuation { pending = $0 } }
        let gateway = router.makeBrowserGateway(allowActions: false, pinnedTabId: tab.id.uuidString, agent: true)
        let read = Task { await gateway.request(["version": 1, "method": "tabs.list", "params": [:]]) }
        while pending == nil { await Task.yield() }
        WindowRegistry.shared.unregister(id: windowId)
        window.orderOut(nil)
        pending?.resume(returning: successResponse(["tabs": [["id": tab.id.uuidString, "title": "private-pinned-title"]]]))
        let response = await read.value
        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual((response["error"] as? [String: Any])?["mayHaveCompleted"] as? Bool, false)
        XCTAssertFalse(BrowserControlGateway.encode(response).contains("private-pinned-title"))
    }
    #endif

    private func snapshot(_ router: Router, tabId: String) async throws -> [String: Any] {
        let result = await router.browserControl(["version": 1, "method": "tab.snapshot", "tabId": tabId, "params": ["maxChars": 2000, "maxElements": 100]])
        XCTAssertEqual(result["ok"] as? Bool, true)
        return try XCTUnwrap(result["value"] as? [String: Any])
    }

    private static let fixture = """
    <!doctype html><title>Isolated browser fixture</title>
    <style>body{font:20px system-ui;padding:20px}button,input{font:20px system-ui;margin:10px}</style>
    <button id="activate">Activate</button><button id="delayed">Delayed</button><label>Entry<input id="entry" value="seed-"></label>
    <div contenteditable="true" aria-label="Editable">editable-secret</div>
    <textarea aria-label="Notes">textarea-secret</textarea><input type="password" value="password-secret" aria-label="Password">
    <script>
      window.activations = 0;
      window.delayedActivations = 0;
      document.getElementById('delayed').onclick = () => {
        window.delayedActivations++;
        const until = Date.now() + 9500;
        while (Date.now() < until) {}
      };
      document.getElementById('activate').onclick = () => window.activations++;
      window.WeakMap = class { set() { throw new Error('page-world spoof'); } get() { return null; } };
      Element.prototype.click = () => window.activations = -1;
    </script>
    """
}
