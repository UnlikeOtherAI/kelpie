import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testCapturedUncertainEditDiscardsMediaAndRedactsAfterCallbackRetires() async throws {
        try await uncertainEdit(capture: true)
    }

    @MainActor
    func testUncapturedUncertainEditRedactsCurrentLiteralAfterCallbackRetires() async throws {
        try await uncertainEdit(capture: false)
    }

    @MainActor
    private func uncertainEdit(capture: Bool) async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let canary = "iOS Reflected+Canary!"
        let variants = [canary, "iOS%20Reflected%2bCanary!", "iOS+Reflected%2bCanary%21"]
        var workflow: Body = [
            "version": 1, "tabId": tab, "actions": [
                ["action": "navigate", "url": "http://127.0.0.1:\(port)/focus-secret-timeout"],
                ["action": "output", "source": "title", "name": "before"],
                ["action": "fill", "target": ["selector": "#entry"], "text": canary]
            ]
        ]
        if capture { workflow["capture"] = ["formats": ["screenshots"]] }
        // The bounded focus handler exceeds the renderer deadline and later returns nonsensitive metadata.
        // The missing-result path must protect this edit before final output/media publication.
        let failed = try await probe.request("/v1/play-script", workflow)
        XCTAssertEqual(failed["success"] as? Bool, false)
        XCTAssertEqual((failed["error"] as? Body)?["code"] as? String, "TIMEOUT")
        XCTAssertEqual(failed["mayHaveCompleted"] as? Bool, true)
        XCTAssertTrue((failed["artifacts"] as? [Body])?.isEmpty == true)
        let prior = try XCTUnwrap((failed["outputs"] as? Body)?["before"] as? String)
        XCTAssertTrue(variants.allSatisfy { !prior.contains($0) })
        let run = try XCTUnwrap(failed["runId"] as? String)
        let status = try await probe.call("kelpie_get_script_status", ["runId": run])
        XCTAssertEqual(status["playing"] as? Bool, false)
        XCTAssertEqual(status["runSuccess"] as? Bool, false)
        XCTAssertEqual((status["runError"] as? Body)?["code"] as? String, "TIMEOUT")
        XCTAssertTrue((status["artifacts"] as? [Body])?.isEmpty == true)
        XCTAssertNil(status["outputs"])
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: [failed, status]), as: UTF8.self)
        XCTAssertTrue(variants.allSatisfy { !serialized.contains($0) })
        let recovered = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "wait", "ms": 1]]
        ])
        XCTAssertEqual(recovered["success"] as? Bool, true, "The original callback must retire before a new run")
        // Input may have occurred after the deadline; this test intentionally makes no zero-input claim.
    }
}
