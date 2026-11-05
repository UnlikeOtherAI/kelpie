import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testPacedFillUsesUnicodeScalarsAndRetainsMedia() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let result = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab,
            "actions": [
                ["action": "navigate", "url": "http://127.0.0.1:\(port)/paced"],
                ["action": "fill", "target": ["selector": "#entry"], "text": "A\u{1F600}B", "typingDelayMs": 120]
            ],
            "capture": ["formats": ["screenshots", "gif", "video"], "fps": 8, "maxWidth": 384]
        ])
        XCTAssertEqual(result["success"] as? Bool, true, WorkflowCaptureProbe.errorCode(result))
        let artifacts = try XCTUnwrap(result["artifacts"] as? [Body])
        XCTAssertGreaterThanOrEqual(artifacts.count, 3)
        let run = try XCTUnwrap(result["runId"] as? String)
        for artifact in artifacts {
            let bytes = try await probe.bytes(artifact, run: run)
            XCTAssertFalse(bytes.isEmpty)
        }
        let events = try await pacedEvents(tab: tab)
        XCTAssertEqual(events.count, 4)
        guard events.count == 4 else { return }
        XCTAssertEqual(events.map { $0["value"] as? String }, ["", "A", "A\u{1F600}", "A\u{1F600}B"])
        let times = try events.map { try XCTUnwrap($0["at"] as? Double) }
        XCTAssertGreaterThanOrEqual(times[2] - times[1], 115)
        XCTAssertGreaterThanOrEqual(times[3] - times[2], 115)
    }

    @MainActor
    func testPacedFocusLossStopsWithoutRetargeting() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let result = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [
                ["action": "navigate", "url": "http://127.0.0.1:\(port)/paced-focus"],
                ["action": "type", "target": ["selector": "#entry"], "text": "AB", "typingDelayMs": 120],
                ["action": "click", "target": ["role": "button", "name": "Submit"]]
            ]
        ])
        XCTAssertEqual((result["error"] as? Body)?["code"] as? String, "INPUT_UNCERTAIN")
        XCTAssertEqual(result["mayHaveCompleted"] as? Bool, true)
        XCTAssertEqual(result["actionsExecuted"] as? Int, 1)
        let events = try await pacedEvents(tab: tab)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?["value"] as? String, "seedA")
    }

    @MainActor
    func testPacedEmptyTypeDoesNotInputAndEmptyFillClears() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let result = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [
                ["action": "navigate", "url": "http://127.0.0.1:\(port)/paced"],
                ["action": "type", "target": ["selector": "#entry"], "text": "", "typingDelayMs": 120],
                ["action": "fill", "target": ["selector": "#entry"], "text": "", "typingDelayMs": 120]
            ], "capture": ["formats": ["screenshots"]]
        ])
        XCTAssertEqual(result["success"] as? Bool, true, WorkflowCaptureProbe.errorCode(result))
        let events = try await pacedEvents(tab: tab)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?["value"] as? String, "")
        XCTAssertGreaterThanOrEqual((result["artifacts"] as? [Body])?.count ?? 0, 3)
    }

    @MainActor
    func testPacedLateSensitivityDiscardsCaptureAndRedactsFullLiteral() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let canary = "iOS Reflected+Canary!"
        let result = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [
                ["action": "navigate", "url": "http://127.0.0.1:\(port)/post-input-secret-autocomplete"],
                ["action": "output", "source": "title", "name": "before"],
                ["action": "type", "target": ["selector": "#entry"], "text": canary, "typingDelayMs": 120],
                ["action": "click", "target": ["role": "button", "name": "Submit"]]
            ], "capture": ["formats": ["screenshots", "gif"]]
        ])
        XCTAssertEqual((result["error"] as? Body)?["code"] as? String, "SENSITIVE_CAPTURE_REFUSED")
        XCTAssertEqual(result["mayHaveCompleted"] as? Bool, true)
        XCTAssertEqual(result["actionsExecuted"] as? Int, 2)
        XCTAssertTrue((result["artifacts"] as? [Body])?.isEmpty == true)
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
        XCTAssertFalse(serialized.contains(canary))
        XCTAssertFalse(serialized.contains("iOS%20Reflected%2bCanary!"))
        let observed = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "output", "source": "title", "name": "events"]]
        ])
        XCTAssertEqual((observed["outputs"] as? Body)?["events"] as? String, "Input 1 Later 0")
    }

    @MainActor
    private func pacedEvents(tab: String) async throws -> [Body] {
        let output = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "output", "source": "title", "name": "events"]]
        ])
        let title = try XCTUnwrap((output["outputs"] as? Body)?["events"] as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(title.utf8)) as? [Body])
    }
}
