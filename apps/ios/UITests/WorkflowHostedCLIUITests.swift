import XCTest

extension WorkflowCaptureUITests {
    /// The dedicated hosted runner starts the shipping CLI when the fixture is ready.
    /// The rendezvous contains the public tab ID and outcome only. Both clients pair through the normal approval sheet.
    @MainActor
    func testHostedCLIUsesPairedWorkflowAndDownloadsEveryFormat() async throws {
        guard let nonce = ProcessInfo.processInfo.environment["KELPIE_WORKFLOW_CLI_PROBE"],
              UUID(uuidString: nonce) != nil,
              let value = ProcessInfo.processInfo.environment["KELPIE_WORKFLOW_CLI_PORT"],
              let port = Int(value), (1...65535).contains(port) else { throw XCTSkip("Requires the hosted CLI acceptance driver") }
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let bridge = WorkflowCaptureProbe(port: port)
        let path = "/" + nonce
        let ready = try await bridge.request(path, ["tabId": tab])
        XCTAssertEqual(ready["accepted"] as? Bool, true)
        let approval = XCUIApplication().buttons["Yes, once"]
        XCTAssertTrue(approval.waitForExistence(timeout: 45))
        approval.tap()
        let deadline = Date().addingTimeInterval(110)
        var outcome = "pending"
        while outcome == "pending", Date() < deadline {
            let status = try await bridge.request(path, method: "GET")
            outcome = try XCTUnwrap(status["state"] as? String)
            if outcome == "pending" { try await Task.sleep(nanoseconds: 200_000_000) }
        }
        XCTAssertEqual(outcome, "passed")
        let verified = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "output", "name": "clicks", "source": "title"]]
        ])
        XCTAssertEqual((verified["outputs"] as? Body)?["clicks"] as? String, "Count 1")
    }
}
