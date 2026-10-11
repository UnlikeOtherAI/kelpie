import WebKit
import XCTest
@testable import Kelpie

@MainActor
final class BrowserControlGatewayTests: XCTestCase {
    func testAuthenticatedRoutesUseCanonicalEnvelopeAndCompactMCP() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PairingStore(storeURL: directory.appendingPathComponent("pairings.json"))
        guard case .created(let pairing) = store.startPairing(clientId: "browser-test", clientName: "test", sourceAddress: "127.0.0.1") else {
            XCTFail("Could not prepare isolated pairing")
            return
        }
        let token = try XCTUnwrap(store.approve(requestId: pairing.requestId, persist: false)?.token)
        let router = Router()
        router.register("get-tabs") { _ in successResponse(["tabs": [["id": "own", "active": true, "url": "about:blank", "title": "Fixture"]]]) }
        #if os(iOS)
        let port: UInt16 = 18439
        #else
        let port: UInt16 = 18429
        #endif
        let server = try HTTPServer(port: port, router: router, pairingStore: store, deviceInfo: DeviceInfo.current(port: Int(port)))
        server.start()
        defer { server.stop() }
        for _ in 0..<50 {
            if (try? await fetch(port: port, path: "/health", body: [:], token: nil, method: "GET"))?.0 == 200 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        for path in ["/v1/browser-control", "/mcp"] {
            let denied = try await fetch(port: port, path: path, body: [:], token: nil)
            XCTAssertEqual(denied.0, 401)
        }
        let unsupportedGet = try await fetch(port: port, path: "/mcp", body: [:], token: token, method: "GET")
        XCTAssertEqual(unsupportedGet.0, 405)
        let badVersion = try await fetch(port: port, path: "/mcp", body: [:], token: token, headers: ["MCP-Protocol-Version": "unsupported"])
        XCTAssertEqual(badVersion.0, 400)
        let browserOrigin = try await fetch(port: port, path: "/mcp", body: [:], token: token, headers: ["Origin": "https://example.test"])
        XCTAssertEqual(browserOrigin.0, 403)
        let list = try await fetch(port: port, path: "/v1/browser-control", body: ["version": 1, "method": "tabs.list", "params": [:]], token: token)
        XCTAssertEqual(list.0, 200)
        XCTAssertEqual(list.1["ok"] as? Bool, true)
        XCTAssertEqual((list.1["value"] as? [[String: Any]])?.first?["id"] as? String, "own")
        let failure = try await fetch(port: port, path: "/v1/browser-control", body: ["version": 1, "method": "tab.click", "tabId": "own", "params": ["ref": "forged"]], token: token)
        XCTAssertEqual(failure.0, 200, "Canonical failures must remain parseable by the shared SDK")
        XCTAssertEqual(failure.1["ok"] as? Bool, false)
        XCTAssertEqual((failure.1["error"] as? [String: Any])?["mayHaveCompleted"] as? Bool, false)
        let initialized = try await fetch(port: port, path: "/mcp", body: [
            "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
                "protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "fixture", "version": "1"]
            ]
        ], token: token)
        XCTAssertEqual(initialized.0, 200)
        let notification = try await fetch(port: port, path: "/mcp", body: ["jsonrpc": "2.0", "method": "notifications/initialized"], token: token)
        XCTAssertEqual(notification.0, 202)
        XCTAssertTrue(notification.1.isEmpty)
        let mcp = try await fetch(port: port, path: "/mcp", body: ["jsonrpc": "2.0", "id": 3, "method": "tools/list"], token: token)
        let tools = (mcp.1["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 4)
        XCTAssertEqual(tools?.first?["name"] as? String, "kelpie_browser_control")
        let internalRoute = try await fetch(port: port, path: "/v1/browser-control-evaluate", body: ["expression": "alert(1)"], token: token)
        XCTAssertEqual(internalRoute.0, 404)
        let unauthenticatedDelete = try await fetch(port: port, path: "/v1/pair", body: [:], token: nil, method: "DELETE")
        XCTAssertEqual(unauthenticatedDelete.0, 401)
        let revoked = try await fetch(port: port, path: "/v1/pair", body: [:], token: token, method: "DELETE")
        XCTAssertEqual(revoked.0, 200)
        let oldBearer = try await fetch(port: port, path: "/v1/browser-control", body: ["version": 1, "method": "tabs.list", "params": [:]], token: token)
        XCTAssertEqual(oldBearer.0, 401, "Authenticated DELETE must revoke only its own pairing")
    }

    func testReadonlyCannotSwitchOrWriteAndSelectedReaderDoesNotRetarget() async {
        var calls: [String] = []
        let gateway = BrowserControlGateway(
            methods: ["get-tabs", "switch-tab", "navigate"],
            extensions: [],
            targeting: "selected",
            allowActions: false,
            dispatch: { method, _, _ in
                calls.append(method)
                return successResponse(["activeTab": "visible", "tabs": [["id": "visible", "active": true]]])
            },
            authorize: { _, mutates in !mutates }
        )
        for method in ["tabs.select", "tab.goto"] {
            let result = await gateway.request(["version": 1, "method": method, "tabId": "other", "params": method == "tab.goto" ? ["url": "https://example.test"] : [:]])
            XCTAssertEqual(result["ok"] as? Bool, false)
        }
        let snapshot = await gateway.request(["version": 1, "method": "tab.snapshot", "tabId": "other", "params": [:]])
        XCTAssertEqual(snapshot["ok"] as? Bool, false)
        XCTAssertEqual(calls, ["get-tabs"], "Readonly inspection cannot implicitly switch the visible renderer")
    }

    func testMutationTimeoutRetainsPendingLeaseThenAllowsExplicitRecovery() async {
        let lease = BrowserControlLease()
        var commands = 0
        let gateway = BrowserControlGateway(
            methods: ["navigate"],
            extensions: [],
            targeting: "direct",
            allowActions: true,
            lease: lease,
            timeoutNanoseconds: 10_000_000,
            dispatch: { _, _, _ in
                commands += 1
                if commands == 1 { try? await Task.sleep(nanoseconds: 100_000_000) }
                return successResponse()
            },
            authorize: { _, _ in true }
        )
        let request: [String: Any] = ["version": 1, "method": "tab.goto", "tabId": "own", "params": ["url": "https://example.test"]]
        let result = await gateway.request(request)
        XCTAssertEqual((result["error"] as? [String: Any])?["mayHaveCompleted"] as? Bool, true)
        let pending = await gateway.request(request)
        XCTAssertEqual((pending["error"] as? [String: Any])?["code"] as? String, "BUSY")
        XCTAssertEqual(commands, 1)
        try? await Task.sleep(nanoseconds: 120_000_000)
        let read = await gateway.request(["version": 1, "method": "documentation", "params": [:]])
        XCTAssertEqual(read["ok"] as? Bool, true)
        XCTAssertEqual(commands, 1, "A late callback cannot replay the timed-out action")
        let explicit = await gateway.request(request)
        XCTAssertEqual(explicit["ok"] as? Bool, true)
        XCTAssertEqual(commands, 2, "A later explicit action works without restarting the app")
    }

    func testCancellationKeepsRendererExclusiveUntilCallbackRetires() async {
        let lease = BrowserControlLease()
        var pending: CheckedContinuation<[String: Any], Never>?
        let gateway = BrowserControlGateway(
            methods: ["navigate"], extensions: [], targeting: "direct", allowActions: true, lease: lease,
            dispatch: { _, _, _ in await withCheckedContinuation { pending = $0 } }, authorize: { _, _ in true }
        )
        let action = Task { await gateway.request(["version": 1, "method": "tab.goto", "tabId": "own", "params": ["url": "https://example.test"]]) }
        while pending == nil { await Task.yield() }
        action.cancel()
        let result = await action.value
        XCTAssertEqual((result["error"] as? [String: Any])?["mayHaveCompleted"] as? Bool, true)
        XCTAssertFalse(lease.begin())
        pending?.resume(returning: successResponse())
        for _ in 0..<100 {
            if lease.begin() { lease.end(); return }
            await Task.yield()
        }
        XCTFail("Retired callback must release control after cancellation")
    }

    func testInferenceExtensionDelegatesLeaseToItsNestedBrowserCalls() async {
        let lease = BrowserControlLease()
        let nested = BrowserControlGateway(
            methods: ["navigate"], extensions: [], targeting: "direct", allowActions: true, lease: lease,
            dispatch: { _, _, _ in successResponse() }, authorize: { _, _ in true }
        )
        let methods = ["ai-infer"]
        let outer = BrowserControlGateway(
            methods: methods, extensions: BrowserControlGateway.extensions(platform: 2, methods: methods), targeting: "direct", allowActions: true, lease: lease,
            dispatch: { _, _, _ in
                let result = await nested.request(["version": 1, "method": "tab.goto", "tabId": "own", "params": ["url": "https://example.test"]])
                return successResponse(["nestedSucceeded": result["ok"] as? Bool ?? false])
            }, authorize: { _, _ in true }
        )
        let result = await outer.callTool(name: "kelpie_extension", arguments: ["name": "kelpie_ai_ask", "arguments": ["prompt": "fixture"]])
        let value = BrowserControlGateway.canonicalResult(result)["value"] as? [String: Any]
        XCTAssertEqual(value?["nestedSucceeded"] as? Bool, true)
    }

    func testPendingInferenceDoesNotOccupyPersistentDirectCoordinator() async {
        let router = Router()
        var pending: CheckedContinuation<[String: Any], Never>?
        router.register("ai-infer") { _ in await withCheckedContinuation { pending = $0 } }
        let inference = Task { await router.browserMCP([
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "kelpie_extension", "arguments": [
                "name": "kelpie_ai_ask", "arguments": ["prompt": "fixture"]
            ]]
        ]) }
        for _ in 0..<100 where pending == nil { await Task.yield() }
        guard let pending else {
            inference.cancel()
            _ = await inference.value
            XCTFail("Inference extension did not reach its admitted native handler")
            return
        }
        let independent = await router.browserControl(["version": 1, "method": "documentation", "params": [:]])
        XCTAssertEqual(independent["ok"] as? Bool, true)
        pending.resume(returning: successResponse(["response": "fixture"]))
        let result = await inference.value
        XCTAssertEqual((result["result"] as? [String: Any])?["isError"] as? Bool, false)
    }

    func testLegacyExtensionRetargetIsRefusedBeforeDispatch() async {
        let dispatcher = RecordingDispatcher()
        let gateway = await dispatcher.browserSession(tabId: "visible", allowActions: true)
        let result = await gateway.callTool(name: "kelpie_extension", arguments: [
            "name": "kelpie_fill", "arguments": ["selector": "#email", "value": "text", "tabId": "other"]
        ])
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertTrue(dispatcher.calls.isEmpty)
    }

    func testLocalReadOnlyAdmissionRetainsRichReadsWithoutWideningRemotePolicy() {
        let local = BrowserAgentAdmission.localReadOnly(vision: false).methods(allowActions: false)
        for method in ["get-cookies", "get-storage", "get-dom", "get-links", "get-js-errors", "get-console-messages", "get-network-log", "get-form-state"] {
            XCTAssertTrue(local.contains(method), "Local read capability must remain admitted: \(method)")
        }
        XCTAssertFalse(local.contains("screenshot"))
        XCTAssertFalse(local.contains("evaluate"))
        XCTAssertFalse(local.contains("click"))
        XCTAssertFalse(local.contains("set-cookie"))
        let vision = BrowserAgentAdmission.localReadOnly(vision: true).methods(allowActions: false)
        XCTAssertTrue(vision.contains("screenshot"))
        XCTAssertFalse(BrowserAgentAdmission.remote.methods(allowActions: false).contains("get-cookies"))
    }

    #if os(macOS)
    func testLocalVisionReceivesOneImageWithoutBase64Text() {
        let bytes = Data([137, 80, 78, 71, 1, 2, 3])
        let encoded = bytes.base64EncodedString()
        let canonical: [String: Any] = ["version": 1, "ok": true, "value": ["type": "image", "mimeType": "image/png"]]
        let result: [String: Any] = ["isError": false, "content": [
            ["type": "image", "mimeType": "image/png", "data": encoded],
            ["type": "text", "text": BrowserControlGateway.encode(canonical)]
        ]]
        let vision = BrowserModelObservation(result, vision: true)
        XCTAssertEqual(vision.image, bytes)
        XCTAssertFalse(BrowserControlGateway.encode(vision.text).contains(encoded))
        let readonlyText = BrowserModelObservation(result, vision: false)
        XCTAssertNil(readonlyText.image)
        XCTAssertFalse(BrowserControlGateway.encode(readonlyText.text).contains(encoded))
        let legacy: [String: Any] = ["isError": false, "content": [["type": "text", "text": BrowserControlGateway.encode([
            "version": 1, "ok": true, "value": ["success": true, "image": encoded, "format": "png"]
        ])]]]
        XCTAssertEqual(BrowserModelObservation(legacy, vision: true).image, bytes)
        XCTAssertFalse(BrowserControlGateway.encode(BrowserModelObservation(legacy, vision: true).text).contains(encoded))
    }
    #endif

    func testProductionBoundaryDiscardsReadAfterRendererChangesDuringDispatch() async {
        let result = await delayedProductionDispatch(method: "get-current-url", requestMethod: "tab.url")
        XCTAssertEqual(result["ok"] as? Bool, false)
        XCTAssertEqual((result["error"] as? [String: Any])?["mayHaveCompleted"] as? Bool, false)
        XCTAssertFalse(BrowserControlGateway.encode(result).contains("private-old-renderer"))
    }

    func testProductionBoundaryKeepsMutationUncertaintyAfterRendererChanges() async {
        let result = await delayedProductionDispatch(method: "navigate", requestMethod: "tab.goto")
        XCTAssertEqual(result["ok"] as? Bool, false)
        XCTAssertEqual((result["error"] as? [String: Any])?["mayHaveCompleted"] as? Bool, true)
    }

    private func delayedProductionDispatch(method: String, requestMethod: String) async -> [String: Any] {
        let context = HandlerContext()
        let router = Router()
        router.handlerContext = context
        #if os(iOS)
        let initial = WKWebView()
        let replacement = WKWebView()
        context.webView = initial
        let tabId = "external"
        router.register("get-tabs") { _ in successResponse() }
        #else
        let tabId = "own"
        #endif
        var pending: CheckedContinuation<[String: Any], Never>?
        router.register(method) { _ in await withCheckedContinuation { pending = $0 } }
        let request = Task { await router.browserControl([
            "version": 1, "method": requestMethod, "tabId": tabId,
            "params": requestMethod == "tab.goto" ? ["url": "https://fixture.test"] : [:]
        ]) }
        while pending == nil { await Task.yield() }
        #if os(iOS)
        context.webView = replacement
        #else
        context.activeEngineIsChromium = true
        #endif
        pending?.resume(returning: successResponse(["url": "private-old-renderer"]))
        return await request.value
    }

    private func fetch(port: UInt16, path: String, body: [String: Any], token: String?, method: String = "POST", headers: [String: String] = [:]) async throws -> (Int, [String: Any]) {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(path)"))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 2
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if method == "POST" { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
    }
}
