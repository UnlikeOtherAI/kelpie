#if os(macOS)
import AppKit
import WebKit
import XCTest
@testable import Kelpie

@MainActor
final class ConnectBrowserControlJobTests: XCTestCase {
    func testJobOwnedCanonicalFixtureSnapshotAppendScreenshotAndDocumentFence() async throws {
        let tab = Tab(spec: TabSpec(persistent: false, dataStore: .nonPersistent()))
        let renderer = tab.renderer
        let store = TabStore(isolatedTab: tab)
        let tabID = tab.id.uuidString
        let windowID = UUID().uuidString
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        guard let webView = renderer.makeView() as? WKWebView else { return XCTFail("Fixture must use WebKit") }
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        WindowRegistry.shared.register(id: windowID, window: window, tabStore: store)
        defer {
            let fixtureTabs = store.tabs
            window.contentView = nil
            window.orderOut(nil)
            fixtureTabs.forEach { $0.renderer.invalidate() }
            WindowRegistry.shared.unregister(id: windowID)
        }

        let context = HandlerContext()
        context.renderer = renderer
        let owner = Router()
        owner.handlerContext = context
        context.browserRouter = owner
        InteractionHandler(context: context).register(on: owner)
        ScreenshotHandler(context: context).register(on: owner)
        NavigationHandler(context: context).register(on: owner)
        ScrollHandler(context: context).register(on: owner)
        owner.register("get-tabs") { _ in
            successResponse(["tabs": store.tabs.map { tab in
                ["id": tab.id.uuidString, "active": tab.id == store.activeTabID, "url": tab.currentURL]
            }])
        }
        owner.register("new-tab") { _ in
            let created = store.addTab()
            window.contentView = created.renderer.makeView()
            return successResponse(["tabId": created.id.uuidString, "tab": ["id": created.id.uuidString]])
        }
        owner.register("switch-tab") { body in
            guard let rawID = body["tabId"] as? String, let id = UUID(uuidString: rawID) else {
                return errorResponse(code: "MISSING_PARAM", message: "tabId required")
            }
            store.selectTab(id: id)
            if let active = store.activeTab { window.contentView = active.renderer.makeView() }
            return successResponse(["tabId": rawID])
        }

        webView.loadHTMLString(Self.fixture, baseURL: URL(string: "https://fixture.test"))
        for _ in 0..<100 {
            if !webView.isLoading, (try? await webView.evaluateJavaScript("!!document.getElementById('entry')")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(webView.isLoading)

        let unboundDispatch: BrowserControlGateway.Dispatch = { method, params, _ in
            await owner.browserDispatch(method: method, params: params, pinnedTabId: nil)
        }
        let listed = await owner.browserControl(
            ["version": 1, "method": "tabs.list", "params": [:]],
            authorizeAccountStep: { _, _ in true }, dispatchAccountStep: unboundDispatch
        )
        XCTAssertEqual(listed["ok"] as? Bool, true)
        XCTAssertTrue((listed["value"] as? [[String: Any]])?.contains { $0["id"] as? String == tabID } == true)
        let created = await owner.browserControl(
            ["version": 1, "method": "tabs.new", "params": [:]],
            authorizeAccountStep: { _, _ in true }, dispatchAccountStep: unboundDispatch
        )
        XCTAssertEqual(created["ok"] as? Bool, true)
        let createdID = try XCTUnwrap((created["value"] as? [String: Any])?["id"] as? String)
        XCTAssertEqual(store.activeTabID?.uuidString, createdID)
        let selected = await owner.browserControl(
            Self.request("tabs.select", tabID: tabID),
            authorizeAccountStep: { _, _ in true }, dispatchAccountStep: unboundDispatch
        )
        XCTAssertEqual(selected["ok"] as? Bool, true)
        XCTAssertEqual(store.activeTabID?.uuidString, tabID)

        let forbiddenAccountNavigation = await ConnectBrowser(context: context).executeControl(
            Self.command(tabID: tabID, version: ConnectDocument.version(renderer)),
            input: ["request": Self.request("tab.goto", tabID: tabID, params: ["url": "https://authentication.unlikeotherai.com/"])]
        )
        XCTAssertEqual(((forbiddenAccountNavigation["response"] as? [String: Any])?["error"] as? [String: Any])?["code"] as? String, "ACCOUNT_SURFACE_FORBIDDEN")

        let command = Self.command(tabID: tabID, version: ConnectDocument.version(renderer))
        let job = try ConnectBrowserControlJob(
            source: context, owner: owner, command: command, tabID: tabID,
            expectedVersion: ConnectDocument.version(renderer), authorized: { true }
        )
        let snapshot = await owner.browserControl(
            Self.request("tab.snapshot", tabID: tabID),
            authorizeAccountStep: { _, _ in true },
            dispatchAccountStep: { method, params, mutates in await job.dispatch(method: method, params: params, mutates: mutates) }
        )
        XCTAssertEqual(snapshot["ok"] as? Bool, true)
        let value = try XCTUnwrap(snapshot["value"] as? [String: Any])
        let elements = try XCTUnwrap(value["elements"] as? [[String: Any]])
        let entry = try XCTUnwrap(elements.first { $0["name"] as? String == "Entry" }?["ref"] as? String)

        let typed = await owner.browserControl(
            Self.request("tab.type", tabID: tabID, params: ["ref": entry, "text": "tail"]),
            authorizeAccountStep: { _, _ in true },
            dispatchAccountStep: { method, params, mutates in await job.dispatch(method: method, params: params, mutates: mutates) }
        )
        XCTAssertEqual(typed["ok"] as? Bool, true)
        let typedValue = try await webView.evaluateJavaScript("document.getElementById('entry').value") as? String
        XCTAssertEqual(typedValue, "seed-tail")

        let screenshot = await owner.browserControl(
            Self.request("tab.screenshot", tabID: tabID),
            authorizeAccountStep: { _, _ in true },
            dispatchAccountStep: { method, params, mutates in await job.dispatch(method: method, params: params, mutates: mutates) }
        )
        let image = try XCTUnwrap((screenshot["value"] as? [String: Any])?["data"] as? String)
        XCTAssertNotNil(Data(base64Encoded: image))

        let otherTab = store.addTab()
        let crossTab = await owner.browserControl(
            Self.request("tab.snapshot", tabID: otherTab.id.uuidString),
            authorizeAccountStep: { _, _ in true },
            dispatchAccountStep: { method, params, mutates in await job.dispatch(method: method, params: params, mutates: mutates) }
        )
        XCTAssertEqual(crossTab["ok"] as? Bool, false)
        store.selectTab(id: tab.id)

        let fresh = await owner.browserControl(
            Self.request("tab.snapshot", tabID: tabID),
            authorizeAccountStep: { _, _ in true },
            dispatchAccountStep: { method, params, mutates in await job.dispatch(method: method, params: params, mutates: mutates) }
        )
        let freshValue = try XCTUnwrap(fresh["value"] as? [String: Any])
        let freshElements = try XCTUnwrap(freshValue["elements"] as? [[String: Any]])
        let button = try XCTUnwrap(freshElements.first { $0["name"] as? String == "Activate" }?["ref"] as? String)
        var changedAtAuthorization = false
        let fenced = await owner.browserControl(
            Self.request("tab.click", tabID: tabID, params: ["ref": button]),
            authorizeAccountStep: { _, _ in
                if !changedAtAuthorization {
                    changedAtAuthorization = true
                    ConnectDocument.navigated(renderer)
                }
                return true
            },
            dispatchAccountStep: { method, params, mutates in await job.dispatch(method: method, params: params, mutates: mutates) }
        )
        XCTAssertEqual(fenced["ok"] as? Bool, false)
        let activations = try await webView.evaluateJavaScript("window.activations") as? Int
        XCTAssertEqual(activations, 0)
    }

    func testNavigationLeaseAllowsOnlyItsIssuedDocumentTransition() {
        let initial = "initial-document"
        let next = "job-navigation"
        let humanReplacement = "human-replacement"
        let navigation = NSObject()
        let lease = ConnectNavigationLease(initial: initial)
        lease.issued(navigation)

        XCTAssertTrue(lease.allowsWait(version: initial, authorized: true))
        lease.started(previous: initial, version: next, navigation: navigation)
        XCTAssertTrue(lease.allowsWait(version: next, authorized: true))
        XCTAssertTrue(lease.allowsRead(version: next, loading: false, authorized: true))
        XCTAssertFalse(lease.allowsRead(version: humanReplacement, loading: false, authorized: true))
        XCTAssertFalse(lease.allowsRead(version: next, loading: false, authorized: false))

        let duplicate = ConnectNavigationLease(initial: initial)
        duplicate.issued(navigation)
        duplicate.started(previous: initial, version: next, navigation: NSObject())
        XCTAssertFalse(duplicate.allowsRead(version: next, loading: false, authorized: true))
    }

    private static func request(_ method: String, tabID: String, params: [String: Any] = [:]) -> [String: Any] {
        ["version": 1, "method": method, "tabId": tabID, "params": params]
    }

    private static func command(tabID: String, version: String) -> [String: Any] {
        [
            "jobId": UUID().uuidString,
            "attemptId": UUID().uuidString,
            "deadline": ISO8601DateFormatter().string(from: Date().addingTimeInterval(60)),
            "tabId": tabID,
            "tabVersion": version
        ]
    }

    private static let fixture = """
    <!doctype html><title>Account browser fixture</title>
    <button id="activate">Activate</button><label>Entry<input id="entry" value="seed-"></label>
    <script>window.activations=0;document.getElementById('activate').onclick=()=>window.activations++;</script>
    """
}
#endif
