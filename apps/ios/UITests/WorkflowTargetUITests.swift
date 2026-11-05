import ImageIO
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
    func testCurveCAndCaptureLimitsAllowNextRun() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let timeout = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "wait", "ms": 1000]],
            "capture": ["formats": ["screenshots"], "maxDurationMs": 100]
        ])
        XCTAssertEqual((timeout["error"] as? Body)?["code"] as? String, "CAPTURE_DURATION_EXCEEDED")
        let tiny = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "screenshot"]],
            "capture": ["formats": ["screenshots"], "maxBytes": 1024, "maxWidth": 640]
        ])
        XCTAssertEqual((tiny["error"] as? Body)?["code"] as? String, "CAPTURE_BUDGET_EXCEEDED")
        let motion = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "tap", "target": ["role": "button", "name": "Submit"]]],
            "pointer": ["enabled": true, "curve": "c", "durationMs": 1200],
            "tapIndicator": ["color": "#F000AA", "radius": 20, "wobble": false, "fade": false],
            "capture": ["formats": ["gif"], "fps": 12, "maxWidth": 384]
        ])
        XCTAssertEqual(motion["success"] as? Bool, true)
        let manifest = try XCTUnwrap((motion["artifacts"] as? [Body])?.first)
        let data = try await probe.bytes(manifest, run: try XCTUnwrap(motion["runId"] as? String))
        let decoder = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertGreaterThan(CGImageSourceGetCount(decoder), 4)
        let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "com.compuserve.gif")
        evidence.name = "C curve with magenta indicator and disabled wobble and fade"
        evidence.lifetime = .keepAlways
        add(evidence)
    }
}
