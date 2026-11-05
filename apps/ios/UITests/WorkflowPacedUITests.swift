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
    func testPacedCaptureKeepsNativeKeyboardClosedDuringEdit() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": "http://127.0.0.1:\(port)/paced"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let script: Body = [
            "version": 1, "tabId": tab,
            "actions": [["action": "type", "target": ["selector": "#entry"], "text": "ABCD", "typingDelayMs": 800]],
            "capture": ["formats": ["gif"], "fps": 10, "maxWidth": 384]
        ]
        let playback = Task.detached { [probe] in try await probe.request("/v1/play-script", script) }
        let application = XCUIApplication()
        XCTAssertTrue(application.buttons["browser.recording.stop"].waitForExistence(timeout: 15))
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let keyboardVisible = application.keyboards.firstMatch.exists
        if keyboardVisible {
            let screenshot = XCTAttachment(screenshot: application.screenshot())
            screenshot.name = "Unexpected keyboard during paced capture"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        let result = try await playback.value
        XCTAssertFalse(keyboardVisible, "Programmatic capture edits should not open the software keyboard")
        XCTAssertEqual(result["success"] as? Bool, true, WorkflowCaptureProbe.errorCode(result))
        let events = try await pacedEvents(tab: tab)
        XCTAssertEqual(events.map { $0["value"] as? String }, ["seedA", "seedAB", "seedABC", "seedABCD"])
        let manifest = try XCTUnwrap((result["artifacts"] as? [Body])?.first)
        let bytes = try await probe.bytes(manifest, run: try XCTUnwrap(result["runId"] as? String))
        XCTAssertGreaterThan(try WorkflowMotionFrames.decode(bytes).count, 2)
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
    func testPacedEmptyTypeRejectsButtonAndReadonlyTargets() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let origin = "http://127.0.0.1:\(port)"
        for (path, selector) in [("/paced", "button"), ("/paced-readonly", "#entry")] {
            let result = try await probe.request("/v1/play-script", [
                "version": 1, "tabId": tab, "actions": [
                    ["action": "navigate", "url": origin + path],
                    ["action": "type", "target": ["selector": selector], "text": "", "typingDelayMs": 120]
                ], "capture": ["formats": ["screenshots"]]
            ])
            XCTAssertEqual((result["error"] as? Body)?["code"] as? String, "TARGET_NOT_EDITABLE")
            XCTAssertEqual(result["actionsExecuted"] as? Int, 1)
            XCTAssertNotEqual(result["mayHaveCompleted"] as? Bool, true)
            let observed = try await probe.request("/v1/play-script", [
                "version": 1, "tabId": tab, "actions": [["action": "output", "source": "title", "name": "title"]]
            ])
            XCTAssertEqual((observed["outputs"] as? Body)?["title"] as? String, "Count 0")
        }
    }

    @MainActor
    func testPacedAcknowledgedFinalNavigationCompletesAndRedacts() async throws {
        try await pacedFinalNavigation(capture: false)
    }

    @MainActor
    func testPacedAcknowledgedFinalNavigationDiscardsCapture() async throws {
        try await pacedFinalNavigation(capture: true)
    }

    @MainActor
    private func pacedFinalNavigation(capture: Bool) async throws {
        let fixture = try WorkflowLoopbackPage()
        _ = try await fixture.start()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let origin = "http://127.0.0.1:\(port)"
        testLaunchArguments = ["--test-paced-final-navigation", origin + "/paced-ack"]
        let tab = try await openOwnedTab(url: "about:blank")
        let canary = "\u{1F9EA}"
        var workflow: Body = [
            "version": 1, "tabId": tab, "actions": [
                ["action": "navigate", "url": origin + "/paced-final-ack"],
                ["action": "output", "source": "title", "name": "before"],
                ["action": "type", "target": ["selector": "#entry"], "text": canary, "typingDelayMs": 1]
            ]
        ]
        if capture { workflow["capture"] = ["formats": ["screenshots"]] }
        let result = try await probe.request("/v1/play-script", workflow)
        XCTAssertEqual(result["success"] as? Bool, !capture, WorkflowCaptureProbe.errorCode(result))
        if capture {
            XCTAssertEqual((result["error"] as? Body)?["code"] as? String, "SENSITIVE_CAPTURE_REFUSED")
            XCTAssertEqual(result["mayHaveCompleted"] as? Bool, true)
            XCTAssertTrue((result["artifacts"] as? [Body])?.isEmpty == true)
        }
        XCTAssertGreaterThan(fixture.requestCount(path: "/paced-ack"), 0)
        let prior = try XCTUnwrap((result["outputs"] as? Body)?["before"] as? String)
        XCTAssertFalse(prior.contains(canary))
    }

    @MainActor
    func testPacedUnknownTargetRedactsFullLiteralButOrdinaryInputDoesNot() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let canary = "iOS Reflected+Canary!"
        for capture in [false, true] {
            var workflow: Body = [
                "version": 1, "tabId": tab, "actions": [
                    ["action": "navigate", "url": "http://127.0.0.1:\(port)/secret-guard"],
                    ["action": "output", "source": "title", "name": "before"],
                    ["action": "type", "target": ["selector": "#missing"], "text": canary, "typingDelayMs": 1]
                ]
            ]
            if capture { workflow["capture"] = ["formats": ["screenshots"]] }
            let failed = try await probe.request("/v1/play-script", workflow)
            XCTAssertEqual((failed["error"] as? Body)?["code"] as? String, "TARGET_NOT_FOUND")
            XCTAssertTrue((failed["artifacts"] as? [Body])?.isEmpty == true)
            let prior = try XCTUnwrap((failed["outputs"] as? Body)?["before"] as? String)
            XCTAssertFalse(prior.contains(canary))
            XCTAssertFalse(prior.contains("iOS%20Reflected%2bCanary!"))
            XCTAssertFalse(prior.contains("iOS+Reflected%2bCanary%21"))
        }
        let ordinary = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [
                ["action": "output", "source": "title", "name": "before"],
                ["action": "type", "target": ["selector": "#entry"], "text": canary, "typingDelayMs": 1]
            ]
        ])
        XCTAssertEqual(ordinary["success"] as? Bool, true, WorkflowCaptureProbe.errorCode(ordinary))
        let prior = try XCTUnwrap((ordinary["outputs"] as? Body)?["before"] as? String)
        XCTAssertTrue(prior.contains(canary), "Known nonsensitive paced input must preserve ordinary output")
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
