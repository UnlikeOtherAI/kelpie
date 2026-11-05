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
        testLaunchArguments.append("--test-g08-document-binding")
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let bridge = WorkflowCaptureProbe(port: port)
        let path = "/" + nonce
        let ready = try await bridge.request(path, ["tabId": tab])
        XCTAssertEqual(ready["accepted"] as? Bool, true)
        // Each host CLI command is a separate process, so the disposable test client
        // needs a persistent exact-socket grant rather than a process-local session.
        let approval = XCUIApplication().buttons["Always allow"]
        XCTAssertTrue(approval.waitForExistence(timeout: 45))
        approval.tap()
        let deadline = Date().addingTimeInterval(720)
        var outcome = "pending"
        var verified = false
        while outcome != "passed", outcome != "failed", Date() < deadline {
            let status = try await bridge.request(path, method: "GET")
            outcome = try XCTUnwrap(status["state"] as? String)
            if outcome == "standard-passed", !verified {
                let result = try await probe.request("/v1/play-script", [
                    "version": 1, "tabId": tab, "actions": [["action": "output", "name": "clicks", "source": "title"]]
                ])
                guard (result["outputs"] as? Body)?["clicks"] as? String == "Count 1" else {
                    XCTFail("Original CLI journey did not preserve its expected title")
                    return
                }
                let acknowledgment = try await bridge.request(path, ["verified": true])
                XCTAssertEqual(acknowledgment["accepted"] as? Bool, true)
                verified = true
            }
            if outcome != "passed", outcome != "failed" {
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        XCTAssertTrue(verified, "Original CLI result was not verified")
        XCTAssertEqual(outcome, "passed")
    }
}
