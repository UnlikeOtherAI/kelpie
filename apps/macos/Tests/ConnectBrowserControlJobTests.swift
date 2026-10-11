#if os(macOS)
import AppKit
import Network
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
        XCTAssertFalse(ConnectBrowser(context: context).supportsControlV1)
        let owner = Router()
        owner.handlerContext = context
        context.browserRouter = owner
        XCTAssertTrue(ConnectBrowser(context: context).supportsControlV1)
        let unavailablePress = await ConnectBrowser(context: context).executeControl(
            Self.command(tabID: tab.id.uuidString, version: ConnectDocument.version(renderer)),
            input: ["request": Self.request("page.press", tabID: tab.id.uuidString, params: ["key": "Enter"])]
        )
        XCTAssertEqual(((unavailablePress["response"] as? [String: Any])?["error"] as? [String: Any])?["code"] as? String, "UNSUPPORTED")
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
        context.activeEngineIsChromium = true
        let hiddenRendererScroll = await job.dispatch(
            method: "scroll", params: ["tabId": tabID, "deltaY": 400.0], mutates: true
        )
        XCTAssertEqual((hiddenRendererScroll["error"] as? [String: Any])?["code"] as? String, "ACCESS_DENIED")
        context.activeEngineIsChromium = false
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

        let server = try LoopbackHTTPFixture(html: Self.fixture)
        let port = try await server.start()
        let destination = "http://127.0.0.1:\(port)/next"
        var gotoDispatch: [String: Any]?
        let goto = await owner.browserControl(
            Self.request("tab.goto", tabID: tabID, params: ["url": destination]),
            authorizeAccountStep: { _, _ in true },
            dispatchAccountStep: { method, params, mutates in
                let result = await job.dispatch(method: method, params: params, mutates: mutates)
                gotoDispatch = result
                return result
            }
        )
        XCTAssertEqual(
            goto["ok"] as? Bool, true,
            "The canonical goto must finish through the job-owned navigation lease; response=\(goto), dispatch=\(String(describing: gotoDispatch)), requestReceived=\(server.receivedRequest)"
        )
        let nextVersion = ConnectDocument.version(renderer)
        XCTAssertNotEqual(nextVersion, command["tabVersion"] as? String)
        let nextCommand = Self.command(tabID: tabID, version: nextVersion)
        let nextJob = try ConnectBrowserControlJob(
            source: context, owner: owner, command: nextCommand, tabID: tabID,
            expectedVersion: nextVersion, authorized: { true }
        )
        let afterGoto = await owner.browserControl(
            Self.request("tab.snapshot", tabID: tabID),
            authorizeAccountStep: { _, _ in true },
            dispatchAccountStep: { method, params, mutates in await nextJob.dispatch(method: method, params: params, mutates: mutates) }
        )
        XCTAssertEqual(afterGoto["ok"] as? Bool, true, "A new outer document pin must authorize the next request")

        let screenshot = await owner.browserControl(
            Self.request("tab.screenshot", tabID: tabID),
            authorizeAccountStep: { _, _ in true },
            dispatchAccountStep: { method, params, mutates in await nextJob.dispatch(method: method, params: params, mutates: mutates) }
        )
        let image = try XCTUnwrap((screenshot["value"] as? [String: Any])?["data"] as? String)
        XCTAssertNotNil(Data(base64Encoded: image))
        XCTAssertEqual((screenshot["value"] as? [String: Any])?["mimeType"] as? String, "image/png",
                       "A screenshot within the result budget keeps the requested PNG")

        let otherTab = store.addTab()
        let crossTab = await owner.browserControl(
            Self.request("tab.snapshot", tabID: otherTab.id.uuidString),
            authorizeAccountStep: { _, _ in true },
            dispatchAccountStep: { method, params, mutates in await nextJob.dispatch(method: method, params: params, mutates: mutates) }
        )
        XCTAssertEqual(crossTab["ok"] as? Bool, false)
        store.selectTab(id: tab.id)

        let fresh = await owner.browserControl(
            Self.request("tab.snapshot", tabID: tabID),
            authorizeAccountStep: { _, _ in true },
            dispatchAccountStep: { method, params, mutates in await nextJob.dispatch(method: method, params: params, mutates: mutates) }
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
            dispatchAccountStep: { method, params, mutates in await nextJob.dispatch(method: method, params: params, mutates: mutates) }
        )
        XCTAssertEqual(fenced["ok"] as? Bool, false)
        let activations = try await webView.evaluateJavaScript("window.activations") as? Int
        XCTAssertEqual(activations, 0)

        let scrollVersion = ConnectDocument.version(renderer)
        let scrollJob = try ConnectBrowserControlJob(
            source: context, owner: owner, command: Self.command(tabID: tabID, version: scrollVersion),
            tabID: tabID, expectedVersion: scrollVersion, authorized: { true }
        )
        let scrollBefore = try await webView.evaluateJavaScript("window.scrollY") as? Double ?? 0
        var changedBeforeScrollDispatch = false
        let fencedScroll = await owner.browserControl(
            Self.request("page.scroll", tabID: tabID, params: ["deltaY": 250]),
            authorizeAccountStep: { _, _ in
                if !changedBeforeScrollDispatch {
                    changedBeforeScrollDispatch = true
                    ConnectDocument.navigated(renderer)
                }
                return true
            },
            dispatchAccountStep: { method, params, mutates in await scrollJob.dispatch(method: method, params: params, mutates: mutates) }
        )
        XCTAssertEqual(fencedScroll["ok"] as? Bool, false)
        let scrollAfter = try await webView.evaluateJavaScript("window.scrollY") as? Double ?? 0
        XCTAssertEqual(scrollAfter, scrollBefore, "The queued scroll effect must not run after its document pin is replaced")

        let delayedServer = try LoopbackHTTPFixture(html: Self.fixture, responseDelay: 500_000_000)
        let delayedPort = try await delayedServer.start()
        var authorized = true
        let cancellationVersion = ConnectDocument.version(renderer)
        let cancellationCommand = Self.command(tabID: tabID, version: cancellationVersion)
        let cancellableJob = try ConnectBrowserControlJob(
            source: context, owner: owner, command: cancellationCommand, tabID: tabID,
            expectedVersion: cancellationVersion, authorized: { authorized }
        )
        let pendingGoto = Task { @MainActor in
            await owner.browserControl(
                Self.request("tab.goto", tabID: tabID, params: ["url": "http://127.0.0.1:\(delayedPort)/late"]),
                authorizeAccountStep: { _, _ in authorized },
                dispatchAccountStep: { method, params, mutates in
                    await cancellableJob.dispatch(method: method, params: params, mutates: mutates)
                }
            )
        }
        for _ in 0..<100 where !delayedServer.receivedRequest {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(delayedServer.receivedRequest, "The native navigation callback should be pending before cancellation")
        pendingGoto.cancel()
        authorized = false
        let cancelled = await pendingGoto.value
        XCTAssertEqual(cancelled["ok"] as? Bool, false)
        XCTAssertFalse(owner.browserLease.begin(), "The pending native callback must retain the browser lease after cancellation")
        var leaseReleased = false
        for _ in 0..<100 {
            if owner.browserLease.begin() {
                owner.browserLease.end()
                leaseReleased = true
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(leaseReleased, "A late renderer callback must eventually retire its retained lease")
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

    func testCEFNavigationDestinationMatchesRootSlashButRejectsRedirects() {
        XCTAssertTrue(ConnectBrowser.navigationDestinationMatches(
            current: "https://example.test/", destination: "https://example.test"
        ))
        XCTAssertFalse(ConnectBrowser.navigationDestinationMatches(
            current: "https://redirect.example.test/", destination: "https://example.test"
        ))
        XCTAssertFalse(ConnectBrowser.navigationDestinationMatches(
            current: "https://example.test/other", destination: "https://example.test"
        ))
    }

    func testIncompressibleAccountScreenshotFallsBackToJpegWithinResultBudget() async throws {
        let tab = Tab(spec: TabSpec(persistent: false, dataStore: .nonPersistent()))
        let renderer = tab.renderer
        let store = TabStore(isolatedTab: tab)
        let tabID = tab.id.uuidString
        let windowID = UUID().uuidString
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        guard let webView = renderer.makeView() as? WKWebView else { return XCTFail("Fixture must use WebKit") }
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        WindowRegistry.shared.register(id: windowID, window: window, tabStore: store)
        defer {
            window.contentView = nil
            window.orderOut(nil)
            renderer.invalidate()
            WindowRegistry.shared.unregister(id: windowID)
        }
        let context = HandlerContext()
        context.renderer = renderer
        let owner = Router()
        owner.handlerContext = context
        context.browserRouter = owner
        ScreenshotHandler(context: context).register(on: owner)

        // Per-pixel random noise defeats PNG compression, like a dense photographic page.
        webView.loadHTMLString("""
        <!doctype html><body style="margin:0"><canvas id="noise"></canvas><script>
        const c=document.getElementById('noise');c.width=innerWidth;c.height=innerHeight;
        const g=c.getContext('2d');const d=g.createImageData(c.width,c.height);
        for(let i=0;i<d.data.length;i++)d.data[i]=i%4===3?255:Math.random()*256|0;
        g.putImageData(d,0,0);document.title='ready';</script></body>
        """, baseURL: URL(string: "https://fixture.test"))
        for _ in 0..<150 {
            if !webView.isLoading, webView.title == "ready" { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(webView.title, "ready")

        let version = ConnectDocument.version(renderer)
        let job = try ConnectBrowserControlJob(
            source: context, owner: owner, command: Self.command(tabID: tabID, version: version),
            tabID: tabID, expectedVersion: version, authorized: { true }
        )
        var formats: [String] = []
        let screenshot = await owner.browserControl(
            Self.request("tab.screenshot", tabID: tabID),
            authorizeAccountStep: { _, _ in true },
            dispatchAccountStep: { method, params, mutates in
                formats.append(params["format"] as? String ?? "png")
                return await job.dispatch(method: method, params: params, mutates: mutates)
            }
        )
        let value = try XCTUnwrap(screenshot["value"] as? [String: Any], "\(screenshot)")
        XCTAssertEqual(value["mimeType"] as? String, "image/jpeg")
        let image = try XCTUnwrap(value["data"] as? String)
        XCTAssertLessThanOrEqual(image.utf8.count, ConnectScreenshotBudget.maxImageCharacters)
        XCTAssertNotNil(NSImage(data: try XCTUnwrap(Data(base64Encoded: image))))
        XCTAssertEqual(formats, ["png"], "The gateway issues one canonical capture; the job owns the fallback")
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
    <!doctype html><title>Account browser fixture</title><div style="height:3000px"></div>
    <button id="activate">Activate</button><label>Entry<input id="entry" value="seed-"></label>
    <script>window.activations=0;document.getElementById('activate').onclick=()=>window.activations++;</script>
    """
}

private final class LoopbackHTTPFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "kelpie.account-browser-fixture")
    private let html: String
    private let responseDelay: UInt64
    private let lock = NSLock()
    private var didReceiveRequest = false
    var receivedRequest: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didReceiveRequest
    }

    init(html: String, responseDelay: UInt64 = 0) throws {
        self.html = html
        self.responseDelay = responseDelay
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = self.listener.port?.rawValue { continuation.resume(returning: port) }
                    else { continuation.resume(throwing: ConnectBrowser.Failure("Fixture listener has no port")) }
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [self] connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                    lock.lock()
                    didReceiveRequest = true
                    lock.unlock()
                    let body = Data(html.utf8)
                    let header = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                    let send = {
                        connection.send(content: header + body, completion: .contentProcessed { _ in connection.cancel() })
                    }
                    if responseDelay == 0 { send() }
                    else { queue.asyncAfter(deadline: .now() + .nanoseconds(Int(responseDelay)), execute: send) }
                }
            }
            listener.start(queue: queue)
        }
    }
}
#endif
