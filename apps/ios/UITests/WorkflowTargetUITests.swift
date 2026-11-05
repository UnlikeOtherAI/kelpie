import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testAmbiguousCoveredAndReplacedTargetsNeverReplay() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let origin = "http://127.0.0.1:" + String(try XCTUnwrap(fixture.listener.port?.rawValue))
        let target: Body = ["role": "button", "name": "Submit"]
        for (path, code) in [("duplicates", "AMBIGUOUS_TARGET"), ("covered", "TARGET_OBSCURED"), ("replace", "INPUT_UNCERTAIN")] {
            let result = try await probe.request("/v1/play-script", [
                "version": 1, "tabId": tab, "actions": [
                    ["action": "navigate", "url": origin + "/" + path],
                    ["action": "click", "target": target]
                ]
            ])
            XCTAssertEqual((result["error"] as? Body)?["code"] as? String, code)
            XCTAssertEqual(result["mayHaveCompleted"] as? Bool ?? false, path == "replace")
            let output = try await probe.request("/v1/play-script", [
                "version": 1, "tabId": tab, "actions": [["action": "output", "name": "title", "source": "title"]]
            ])
            XCTAssertEqual((output["outputs"] as? Body)?["title"] as? String, path == "replace" ? "Pointerdown 1" : "Count 0")
        }
    }

    @MainActor
    func testLabelFillTypeAndReflectedPasswordRedaction() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let entry: Body = ["label": "Entry"]
        let edit: [Body] = [
            ["action": "fill", "target": entry, "text": "A"],
            ["action": "type", "target": entry, "text": "B"],
            ["action": "extract", "name": "length", "params": ["fields": [["name": "length", "source": "text", "selector": "#length"]]]]
        ]
        let result = try await probe.request("/v1/play-script", ["version": 1, "tabId": tab, "actions": edit])
        let length = try XCTUnwrap((result["outputs"] as? Body)?["length"] as? Body)
        XCTAssertEqual((length["fields"] as? [Body])?.first?["values"] as? [String], ["2"])
        let canary = "iOS-Fixture+Private!"
        let reflection: [Body] = [
            ["action": "fill", "target": ["selector": "input[type=password]"], "text": canary],
            ["action": "output", "name": "title", "source": "title"]
        ]
        let secured = try await probe.request("/v1/play-script", ["version": 1, "tabId": tab, "actions": reflection])
        XCTAssertEqual(secured["success"] as? Bool, true)
        XCTAssertFalse(String(decoding: try JSONSerialization.data(withJSONObject: secured), as: UTF8.self).contains(canary))
        XCTAssertNotNil((secured["outputs"] as? Body)?["title"])
    }

    @MainActor
    func testCaptureLimitsRecoverAndBothPointerCurvesReachTheirTarget() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let timeout = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [
                ["action": "wait", "ms": 1000], ["action": "tap", "target": ["role": "button", "name": "Submit"]]
            ],
            "capture": ["formats": ["screenshots"], "maxDurationMs": 100]
        ])
        XCTAssertEqual((timeout["error"] as? Body)?["code"] as? String, "CAPTURE_DURATION_EXCEEDED")
        XCTAssertEqual(timeout["actionsExecuted"] as? Int, 0)
        let preserved = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "output", "source": "title", "name": "count"]]
        ])
        XCTAssertEqual((preserved["outputs"] as? Body)?["count"] as? String, "Count 0")
        let tiny = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "screenshot"]],
            "capture": ["formats": ["screenshots"], "maxBytes": 1024, "maxWidth": 640]
        ])
        XCTAssertEqual((tiny["error"] as? Body)?["code"] as? String, "CAPTURE_BUDGET_EXCEEDED")
        let origin = "http://127.0.0.1:" + String(try XCTUnwrap(fixture.listener.port?.rawValue))
        let navigated = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": origin + "/motion"]]
        ])
        XCTAssertEqual(navigated["success"] as? Bool, true)
        for curve in ["s", "c"] {
            let animated = curve == "s"
            let motion = try await probe.call("kelpie_play_script", [
                "version": 1, "tabId": tab, "actions": [
                    ["action": "tap", "target": ["role": "button", "name": "Track"]],
                    ["action": "output", "source": "title", "name": "clicked"]
                ],
                "pointer": ["enabled": true, "curve": curve, "durationMs": 1800],
                "tapIndicator": ["color": "#F000AA", "radius": 32, "durationMs": 1400, "wobble": animated, "fade": animated],
                "capture": ["formats": ["gif"], "fps": 15, "maxWidth": 512]
            ])
            XCTAssertEqual(motion["success"] as? Bool, true)
            XCTAssertEqual((motion["outputs"] as? Body)?["clicked"] as? String, "Track clicked")
            let manifest = try XCTUnwrap((motion["artifacts"] as? [Body])?.first)
            let data = try await probe.bytes(manifest, run: try XCTUnwrap(motion["runId"] as? String))
            let frames = try WorkflowMotionFrames.decode(data)
            let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "com.compuserve.gif")
            evidence.name = "\(curve.uppercased()) curve with magenta indicator"
            evidence.lifetime = .keepAlways
            add(evidence)
            let measurements = frames.map { "\($0.time)\t\($0.pointer?.x ?? -1)\t\($0.pointer?.y ?? -1)\t\($0.indicatorWidth)\t\($0.colorStrength)" }
            let trace = XCTAttachment(string: "PTS\tx\ty\tindicator width\tred minus green\n" + measurements.joined(separator: "\n"))
            trace.name = "\(curve.uppercased()) captured pointer and indicator measurements"
            trace.lifetime = .keepAlways
            add(trace)
            try WorkflowMotionFrames.verify(frames, curve: curve)
        }
    }
}
