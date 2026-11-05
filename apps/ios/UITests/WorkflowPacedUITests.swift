import UIKit
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
        try await pacedCaptureKeyboardCheck()
    }

    @MainActor
    func testKeyboardGeometryForOwnedPacedCapture() async throws {
        testLaunchArguments = ["--test-keyboard-geometry"]
        try await pacedCaptureKeyboardCheck()
    }

    @MainActor
    func testPostEvaluationCallbackKeepsKeyboardClosed() async throws {
        testLaunchArguments = ["--test-post-evaluation"]
        try await pacedCaptureKeyboardCheck()
    }

    @MainActor
    private func pacedCaptureKeyboardCheck() async throws {
        let (fixture, tab) = try await ready()
        continueAfterFailure = true
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": "http://127.0.0.1:\(port)/paced"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let isGeometryProof = testLaunchArguments.contains("--test-keyboard-geometry")
        let beforeGeometry = isGeometryProof ? try await keyboardFixtureGeometry(tab: tab) : [:]
        let beforeSnapshot = isGeometryProof ? try await keyboardFixtureSnapshot(tab: tab) : nil
        if isGeometryProof {
            let confirmed = try await keyboardFixtureGeometry(tab: tab)
            XCTAssertEqual(NSDictionary(dictionary: beforeGeometry), NSDictionary(dictionary: confirmed))
        }
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
        if let beforeSnapshot {
            let afterGeometry = try await keyboardFixtureGeometry(tab: tab)
            let afterSnapshot = try await keyboardFixtureSnapshot(tab: tab)
            let confirmedGeometry = try await keyboardFixtureGeometry(tab: tab)
            let geometry = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
                "before": beforeGeometry, "after": afterGeometry, "afterSnapshot": confirmedGeometry
            ], options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
            geometry.name = "Owned fixture visual geometry before and after editing"
            geometry.lifetime = .keepAlways
            add(geometry)
            XCTAssertEqual(beforeGeometry["scene"] as? String, afterGeometry["scene"] as? String)
            XCTAssertEqual(NSDictionary(dictionary: afterGeometry), NSDictionary(dictionary: confirmedGeometry))
            try retainFixedCanvasProof(before: beforeSnapshot, after: afterSnapshot)
        }
        let facts: Body = ["keyboardVisible": keyboardVisible, "success": result["success"] as? Bool ?? false,
                           "errorCode": WorkflowCaptureProbe.errorCode(result),
                           "artifactCount": (result["artifacts"] as? [Body])?.count ?? 0]
        let report = XCTAttachment(data: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]),
                                   uniformTypeIdentifier: "public.json")
        report.name = "Paced capture outcome and keyboard observation"
        report.lifetime = .keepAlways
        add(report)
        XCTAssertFalse(keyboardVisible, "Programmatic capture edits should not open the software keyboard")
        XCTAssertEqual(result["success"] as? Bool, true, WorkflowCaptureProbe.errorCode(result))
        let events = try await pacedEvents(tab: tab)
        XCTAssertEqual(events.map { $0["value"] as? String }, ["seedA", "seedAB", "seedABC", "seedABCD"])
        let manifest = try XCTUnwrap((result["artifacts"] as? [Body])?.first)
        let bytes = try await probe.bytes(manifest, run: try XCTUnwrap(result["runId"] as? String))
        XCTAssertGreaterThan(try WorkflowMotionFrames.decode(bytes).count, 2)
    }

    private func keyboardFixtureSnapshot(tab: String) async throws -> Data {
        let response = try await probe.request("/v1/browser-control", [
            "version": 1, "tabId": tab, "method": "tab.screenshot", "params": [:]
        ])
        let value = try XCTUnwrap(response["value"] as? Body)
        let encoded = try XCTUnwrap(value["data"] as? String)
        return try XCTUnwrap(Data(base64Encoded: encoded))
    }

    private func retainFixedCanvasProof(before: Data, after: Data) throws {
        let first = try XCTUnwrap(UIImage(data: before)?.cgImage)
        let second = try XCTUnwrap(UIImage(data: after)?.cgImage)
        let factor = CGFloat(first.width) / CGFloat(second.width)
        let height = CGFloat(second.height) * factor
        XCTAssertLessThanOrEqual(height, CGFloat(first.height) + 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: first.width, height: first.height), format: format).image { renderer in
            UIColor.black.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: first.width, height: first.height))
            UIImage(cgImage: second).draw(in: CGRect(x: 0, y: 0, width: CGFloat(first.width), height: height))
        }
        for (name, data) in [("Original WK snapshot", before), ("Keyboard WK snapshot", after),
                             ("Unstretched fixed-canvas candidate", try XCTUnwrap(image.pngData()))] {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = XCTAttachment.Lifetime.keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func keyboardFixtureGeometry(tab: String) async throws -> Body {
        let response = try await probe.request("/v1/browser-control", [
            "version": 1, "tabId": tab, "method": "tab.extract",
            "params": ["fields": [["name": "geometry", "selector": "#keyboard-geometry", "source": "text"]]]
        ])
        let value = try XCTUnwrap(response["value"] as? Body)
        let text = try XCTUnwrap(((value["fields"] as? [Body])?.first?["values"] as? [String])?.first)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? Body)
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
