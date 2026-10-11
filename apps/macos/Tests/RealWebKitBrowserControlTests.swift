import WebKit
#if os(iOS)
import Network
#endif
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

    #if os(iOS)
    func testAccountJobOwnsCanonicalGotoAndFreshDocumentPin() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 800), configuration: configuration)
        let tab = BrowserTab(webView: webView, isStartPage: false, recordsHistory: false)
        let store = TabStore(isolatedTab: tab)
        let context = HandlerContext()
        context.webView = webView
        context.tabStore = store
        let owner = Router()
        owner.handlerContext = context
        context.browserRouter = owner
        InteractionHandler(context: context).register(on: owner)
        NavigationHandler(context: context).register(on: owner)
        ScreenshotHandler(context: context).register(on: owner)
        ScrollHandler(context: context).register(on: owner)
        ConnectSnapshot(context: context).register(on: owner)
        let tabId = tab.id.uuidString
        owner.register("get-tabs") { _ in
            successResponse(["tabs": [["id": tabId, "active": true, "url": webView.url?.absoluteString ?? ""]]])
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 640, height: 800)
        let container = UIView(frame: window.bounds)
        let controller = UIViewController()
        controller.view = container
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let browserState = BrowserState()
        let coordinator = TabWebViewContainer.Coordinator(
            browserState: browserState, handlerContext: context,
            onScrollDirectionChange: { _ in }, onWebViewReady: { _ in }
        )
        coordinator.install(webView: webView, in: container)
        defer {
            window.isHidden = true
            tab.invalidate()
        }

        webView.loadHTMLString("<title>Initial account fixture</title><p>Ready</p>", baseURL: URL(string: "https://initial.fixture.test"))
        for _ in 0..<100 where webView.isLoading {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(webView.isLoading)

        let fixture = Self.fixture.replacingOccurrences(of: "9500", with: "1500")
        let server = try LoopbackWebKitFixture(html: fixture)
        let port = try await server.start()
        var authorized = true
        func job(version: String) throws -> ConnectBrowserControlJob {
            let command = Self.command(tabID: tabId, version: version)
            return try ConnectBrowserControlJob(
                source: context, owner: owner, command: command, tabID: tabId,
                expectedVersion: version, authorized: { authorized }
            )
        }
        func request(_ method: String, params: [String: Any] = [:]) -> [String: Any] {
            ["version": 1, "method": method, "tabId": tabId, "params": params]
        }
        func run(_ request: [String: Any], through job: ConnectBrowserControlJob) async -> [String: Any] {
            await owner.browserControl(
                request, authorizeAccountStep: { _, _ in authorized },
                dispatchAccountStep: { method, params, mutates in
                    await job.dispatch(method: method, params: params, mutates: mutates)
                }
            )
        }

        let initialVersion = ConnectDocument.version(webView)
        let goto = await run(
            request("tab.goto", params: ["url": "http://127.0.0.1:\(port)/account-fixture"]),
            through: try job(version: initialVersion)
        )
        XCTAssertEqual(goto["ok"] as? Bool, true, "Canonical goto should finish through the issued WKNavigation lease: \(goto)")
        XCTAssertTrue(server.receivedRequest)
        let nextVersion = ConnectDocument.version(webView)
        XCTAssertNotEqual(nextVersion, initialVersion)

        let nextJob = try job(version: nextVersion)
        let snapshot = await run(request("tab.snapshot"), through: nextJob)
        XCTAssertEqual(snapshot["ok"] as? Bool, true)
        let elements = try XCTUnwrap((snapshot["value"] as? [String: Any])?["elements"] as? [[String: Any]])
        let entry = try XCTUnwrap(elements.first { $0["name"] as? String == "Entry" }?["ref"] as? String)
        let typed = await run(request("tab.type", params: ["ref": entry, "text": "tail"]), through: nextJob)
        XCTAssertEqual(typed["ok"] as? Bool, true)
        let typedValue = try await webView.evaluateJavaScript("document.getElementById('entry').value") as? String
        XCTAssertEqual(typedValue, "seed-tail")

        let fresh = await run(request("tab.snapshot"), through: nextJob)
        let freshElements = try XCTUnwrap((fresh["value"] as? [String: Any])?["elements"] as? [[String: Any]])
        let button = try XCTUnwrap(freshElements.first { $0["name"] as? String == "Activate" }?["ref"] as? String)
        var replacedBeforeDispatch = false
        let refused = await owner.browserControl(
            request("tab.click", params: ["ref": button]),
            authorizeAccountStep: { _, _ in
                if !replacedBeforeDispatch {
                    replacedBeforeDispatch = true
                    ConnectDocument.navigated(webView)
                }
                return true
            },
            dispatchAccountStep: { method, params, mutates in
                await nextJob.dispatch(method: method, params: params, mutates: mutates)
            }
        )
        XCTAssertEqual(refused["ok"] as? Bool, false)
        let activationCount = try await webView.evaluateJavaScript("window.activations") as? Int
        XCTAssertEqual(activationCount, 0)

        let cancellationVersion = ConnectDocument.version(webView)
        let cancellationJob = try job(version: cancellationVersion)
        let delayedSnapshot = await run(request("tab.snapshot"), through: cancellationJob)
        let delayedElements = try XCTUnwrap((delayedSnapshot["value"] as? [String: Any])?["elements"] as? [[String: Any]])
        let delayedRef = try XCTUnwrap(delayedElements.first { $0["name"] as? String == "Delayed" }?["ref"] as? String)
        let action = Task { await run(request("tab.click", params: ["ref": delayedRef]), through: cancellationJob) }
        try await Task.sleep(nanoseconds: 100_000_000)
        action.cancel()
        authorized = false
        let cancelled = await action.value
        XCTAssertEqual((cancelled["error"] as? [String: Any])?["mayHaveCompleted"] as? Bool, true)
        XCTAssertFalse(owner.browserLease.begin(), "Cancellation must retain the lease while the WK callback is pending")
        var retired = false
        for _ in 0..<100 {
            if owner.browserLease.begin() {
                owner.browserLease.end()
                retired = true
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(retired, "The actual WK callback must retire the cancelled job lease")
    }
    #endif

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

    #if os(iOS)
    private static func command(tabID: String, version: String) -> [String: Any] {
        [
            "jobId": UUID().uuidString,
            "attemptId": UUID().uuidString,
            "deadline": ISO8601DateFormatter().string(from: Date().addingTimeInterval(60)),
            "tabId": tabID,
            "tabVersion": version
        ]
    }
    #endif

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

#if os(iOS)
private final class LoopbackWebKitFixture: @unchecked Sendable {
    private let html: String
    private let listener: NWListener
    private let lock = NSLock()
    private var received = false
    private let queue = DispatchQueue(label: "kelpie.ios.account-control-fixture")

    var receivedRequest: Bool {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    init(html: String) throws {
        self.html = html
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = self.listener.port?.rawValue else {
                        continuation.resume(throwing: NSError(domain: "KelpieFixture", code: 1))
                        return
                    }
                    continuation.resume(returning: port)
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: self.queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, error in
                    guard error == nil else { connection.cancel(); return }
                    self.lock.lock()
                    self.received = true
                    self.lock.unlock()
                    let body = Data(self.html.utf8)
                    var response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                    response.append(body)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            listener.start(queue: queue)
        }
    }
}
#endif
