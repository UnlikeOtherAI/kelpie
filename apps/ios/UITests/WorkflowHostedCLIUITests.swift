import XCTest

extension WorkflowCaptureUITests {
    /// The dedicated hosted runner starts the shipping CLI when the fixture is ready.
    /// The rendezvous contains the public tab ID and outcome only. Both clients pair through the normal approval sheet.
    @MainActor
    func testHostedCLIUsesPairedWorkflowAndDownloadsEveryFormat() async throws {
        guard let nonce = ProcessInfo.processInfo.environment["KELPIE_WORKFLOW_CLI_PROBE"],
              UUID(uuidString: nonce) != nil else { throw XCTSkip("Requires the hosted CLI acceptance driver") }
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let inbox = documents.appendingPathComponent("kelpie-cli-" + nonce, isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try Data(tab.utf8).write(to: inbox.appendingPathComponent("ready"), options: .atomic)
        let approval = XCUIApplication().buttons["Yes, once"]
        XCTAssertTrue(approval.waitForExistence(timeout: 45))
        approval.tap()
        let deadline = Date().addingTimeInterval(110)
        let done = inbox.appendingPathComponent("result")
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTAssertEqual(try String(contentsOf: done, encoding: .utf8), "passed")
        let verified = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "output", "name": "clicks", "source": "title"]]
        ])
        XCTAssertEqual((verified["outputs"] as? Body)?["clicks"] as? String, "Count 1")
    }
}
