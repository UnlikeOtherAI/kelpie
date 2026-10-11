import XCTest
@testable import Kelpie

@MainActor
final class BrowserControlGatewayTests: XCTestCase {
    func testAuthenticatedRoutesUseCanonicalEnvelopeAndCompactMCP() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PairingStore(storeURL: directory.appendingPathComponent("pairings.json"))
        guard case .created(let pairing) = store.startPairing(clientId: "browser-test", clientName: "test", sourceAddress: "127.0.0.1") else {
            XCTFail("Could not prepare isolated pairing")
            return
        }
        let token = try XCTUnwrap(store.approve(requestId: pairing.requestId, persist: false)?.token)
        let router = Router()
        router.register("get-tabs") { _ in successResponse(["tabs": [["id": "own", "active": true, "url": "about:blank", "title": "Fixture"]]]) }
        let port: UInt16 = 18429
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
        let list = try await fetch(port: port, path: "/v1/browser-control", body: ["version": 1, "method": "tabs.list", "params": [:]], token: token)
        XCTAssertEqual(list.0, 200)
        XCTAssertEqual(list.1["ok"] as? Bool, true)
        XCTAssertEqual((list.1["value"] as? [[String: Any]])?.first?["id"] as? String, "own")
        let failure = try await fetch(port: port, path: "/v1/browser-control", body: ["version": 1, "method": "tab.click", "tabId": "own", "params": ["ref": "forged"]], token: token)
        XCTAssertEqual(failure.0, 200, "Canonical failures must remain parseable by the shared SDK")
        XCTAssertEqual(failure.1["ok"] as? Bool, false)
        XCTAssertEqual((failure.1["error"] as? [String: Any])?["mayHaveCompleted"] as? Bool, false)
        let mcp = try await fetch(port: port, path: "/mcp", body: ["jsonrpc": "2.0", "id": 3, "method": "tools/list"], token: token)
        let tools = (mcp.1["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 4)
        XCTAssertEqual(tools?.first?["name"] as? String, "kelpie_browser_control")
        let internalRoute = try await fetch(port: port, path: "/v1/browser-control-evaluate", body: ["expression": "alert(1)"], token: token)
        XCTAssertEqual(internalRoute.0, 404)
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

    func testMutationTimeoutQuarantinesLeaseAndNeverReplays() async {
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
                try? await Task.sleep(nanoseconds: 100_000_000)
                return successResponse()
            },
            authorize: { _, _ in true }
        )
        let request: [String: Any] = ["version": 1, "method": "tab.goto", "tabId": "own", "params": ["url": "https://example.test"]]
        let result = await gateway.request(request)
        XCTAssertEqual((result["error"] as? [String: Any])?["mayHaveCompleted"] as? Bool, true)
        _ = await gateway.request(request)
        XCTAssertEqual(commands, 1)
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertFalse(lease.begin(), "A timed-out mutation requires an explicit browser restart")
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

    private func fetch(port: UInt16, path: String, body: [String: Any], token: String?, method: String = "POST") async throws -> (Int, [String: Any]) {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(path)"))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 2
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if method == "POST" { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
    }
}
