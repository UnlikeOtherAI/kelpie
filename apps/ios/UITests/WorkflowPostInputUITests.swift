import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testPostInputPasswordCaptureStopsLaterActionsAndDiscardsMedia() async throws {
        try await postInputSensitivity(kind: "password", capture: true)
    }

    @MainActor
    func testPostInputAutocompleteCaptureStopsLaterActionsAndDiscardsMedia() async throws {
        try await postInputSensitivity(kind: "autocomplete", capture: true)
    }

    @MainActor
    func testPostInputPasswordWithoutCaptureCompletesAndScrubsOutputs() async throws {
        try await postInputSensitivity(kind: "password", capture: false)
    }

    @MainActor
    func testPostInputAutocompleteWithoutCaptureCompletesAndScrubsOutputs() async throws {
        try await postInputSensitivity(kind: "autocomplete", capture: false)
    }

    @MainActor
    private func postInputSensitivity(kind: String, capture: Bool) async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let canary = "iOS Reflected+Canary!"
        let variants = [canary, "iOS%20Reflected%2bCanary!", "iOS+Reflected%2bCanary%21"]
        var workflow: Body = [
            "version": 1, "tabId": tab, "actions": [
                ["action": "navigate", "url": "http://127.0.0.1:\(port)/post-input-secret-" + kind],
                ["action": "output", "source": "title", "name": "before"],
                ["action": "fill", "target": ["selector": "#entry"], "text": canary],
                ["action": "click", "target": ["role": "button", "name": "Submit"]],
                ["action": "output", "source": "title", "name": "after"]
            ]
        ]
        if capture { workflow["capture"] = ["formats": ["screenshots"]] }
        if capture {
            let name = kind == "password" ? "kelpie_play_script" : "kelpie_extension"
            let arguments: Body = kind == "password" ? workflow : ["name": "kelpie_play_script", "arguments": workflow]
            let envelope = try await probe.toolEnvelope(name, arguments)
            XCTAssertEqual(envelope["ok"] as? Bool, false)
            XCTAssertEqual((envelope["error"] as? Body)?["code"] as? String, "COMMAND_FAILED")
            let metadata = try await probe.call("kelpie_get_script_status", [:])
            XCTAssertEqual(metadata["runSuccess"] as? Bool, false)
            XCTAssertEqual(metadata["mayHaveCompleted"] as? Bool, true)
            XCTAssertEqual((metadata["runError"] as? Body)?["code"] as? String, "SENSITIVE_CAPTURE_REFUSED")
            XCTAssertTrue((metadata["artifacts"] as? [Body])?.isEmpty == true)
            XCTAssertNil(metadata["outputs"])
            let exposed = String(decoding: try JSONSerialization.data(withJSONObject: [envelope, metadata]), as: UTF8.self)
            XCTAssertTrue(variants.allSatisfy { !exposed.contains($0) })
        }
        let result = capture ? try await probe.request("/v1/play-script", workflow) :
            try await probe.call("kelpie_play_script", workflow)
        XCTAssertEqual(result["success"] as? Bool, !capture)
        XCTAssertEqual(result["actionsExecuted"] as? Int, capture ? 2 : 5)
        XCTAssertTrue((result["artifacts"] as? [Body])?.isEmpty == true)
        if capture {
            XCTAssertEqual((result["error"] as? Body)?["code"] as? String, "SENSITIVE_CAPTURE_REFUSED")
            XCTAssertEqual(result["mayHaveCompleted"] as? Bool, true)
            XCTAssertNil((result["outputs"] as? Body)?["after"])
        } else {
            XCTAssertEqual((result["outputs"] as? Body)?["after"] as? String, "Input 1 Later 1")
        }
        let prior = try XCTUnwrap((result["outputs"] as? Body)?["before"] as? String)
        XCTAssertTrue(variants.allSatisfy { !prior.contains($0) })
        let status = try await probe.call("kelpie_get_script_status", ["runId": try XCTUnwrap(result["runId"] as? String)])
        XCTAssertEqual(status["playing"] as? Bool, false)
        XCTAssertEqual(status["runSuccess"] as? Bool, !capture)
        XCTAssertTrue((status["artifacts"] as? [Body])?.isEmpty == true)
        XCTAssertNil(status["outputs"])
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: [result, status]), as: UTF8.self)
        XCTAssertTrue(variants.allSatisfy { !serialized.contains($0) })
        let observed = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "output", "source": "title", "name": "events"]]
        ])
        XCTAssertEqual((observed["outputs"] as? Body)?["events"] as? String, capture ? "Input 1 Later 0" : "Input 1 Later 1")
    }
}
