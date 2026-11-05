import UIKit

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
        XCTAssertEqual(result["success"] as? Bool, true, "Workflow error: " + WorkflowCaptureProbe.errorCode(result))
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
    func testDefaultPointerMotionUsesShorterNativeTiming() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": "http://127.0.0.1:\(port)/motion"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let result = try await probe.call("kelpie_play_script", [
            "version": 1, "tabId": tab,
            "actions": [["action": "tap", "target": ["role": "button", "name": "Track"]],
                        ["action": "output", "source": "title", "name": "clicked"]],
            "pointer": ["enabled": true],
            "tapIndicator": ["color": "#F000AA", "radius": 32, "durationMs": 700],
            "capture": ["formats": ["gif"], "fps": 30, "maxWidth": 512]
        ])
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual((result["outputs"] as? Body)?["clicked"] as? String, "Track clicked")
        let manifest = try XCTUnwrap((result["artifacts"] as? [Body])?.first)
        let bytes = try await probe.bytes(manifest, run: try XCTUnwrap(result["runId"] as? String))
        let frames = try WorkflowMotionFrames.decode(bytes)
        let marker = try XCTUnwrap(frames.firstIndex { $0.indicatorWidth > 0 })
        let travel = frames[..<marker].filter { $0.pointer != nil }
        let evidence = XCTAttachment(data: bytes, uniformTypeIdentifier: "com.compuserve.gif")
        evidence.name = "Default pointer timing GIF"
        evidence.lifetime = .keepAlways
        add(evidence)
        let trace = XCTAttachment(string: frames.map {
            "\($0.time)\t\($0.pointer?.x ?? -1)\t\($0.pointer?.y ?? -1)\t\($0.indicatorWidth)"
        }.joined(separator: "\n"))
        trace.name = "Default pointer decoded frame timing"
        trace.lifetime = .keepAlways
        add(trace)
        XCTAssertGreaterThanOrEqual(travel.count, 3, "Need multiple decoded in-motion frames")
        let first = try XCTUnwrap(travel.first)
        let start = try XCTUnwrap(first.pointer)
        let end = try XCTUnwrap(travel.last?.pointer)
        XCTAssertGreaterThan(hypot(end.x - start.x, end.y - start.y), 10)
        let elapsed = frames[marker].time - first.time
        XCTAssertGreaterThan(elapsed, 0.12)
        XCTAssertLessThan(elapsed, 0.5, "Default pointer movement should finish in under half a second")
    }

    @MainActor
    func testLivePointerMarkerAndStopAppearDuringCapture() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": "http://127.0.0.1:\(port)/motion"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let script: Body = [
            "version": 1, "tabId": tab,
            "actions": [["action": "wait", "ms": 1000], ["action": "tap", "target": ["role": "button", "name": "Track"]]],
            "pointer": ["enabled": true, "durationMs": 2400, "curve": "c"],
            "tapIndicator": ["color": "#F000AA", "radius": 32, "durationMs": 2200],
            "capture": ["formats": ["gif"], "fps": 15, "maxWidth": 512]
        ]
        let playback = Task.detached { [probe] in try await probe.call("kelpie_play_script", script) }
        let application = XCUIApplication()
        let stop = application.buttons["browser.recording.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(12)
        var pointer: XCUIScreenshot?
        var marker: XCUIScreenshot?
        repeat {
            let screen = application.screenshot()
            if let image = screen.image.cgImage {
                let crop = CGRect(x: Double(image.width) * 0.1, y: Double(image.height) * 0.1,
                                  width: Double(image.width) * 0.8, height: Double(image.height) * 0.7).integral
                if let center = image.cropping(to: crop), let sample = try? WorkflowMotionFrames.measure(center, time: 0) {
                    if sample.pointer != nil && sample.indicatorWidth == 0 && pointer == nil { pointer = screen }
                    if sample.indicatorWidth > 0 && marker == nil { marker = screen }
                }
            }
            if pointer != nil && marker != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline && stop.exists
        if let pointer {
            let attachment = XCTAttachment(screenshot: pointer)
            attachment.name = "Live native pointer and recording Stop"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        if let marker {
            let attachment = XCTAttachment(screenshot: marker)
            attachment.name = "Live native tap marker and recording Stop"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let result = try await playback.value
        XCTAssertEqual(result["success"] as? Bool, true, WorkflowCaptureProbe.errorCode(result))
        XCTAssertNotNil(pointer, "A live pointer frame must be visible in the native window")
        XCTAssertNotNil(marker, "A live marker frame must be visible in the native window")
        let manifest = try XCTUnwrap((result["artifacts"] as? [Body])?.first)
        let bytes = try await probe.bytes(manifest, run: try XCTUnwrap(result["runId"] as? String))
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "com.compuserve.gif")
        attachment.name = "Live pointer journey exported GIF"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(try WorkflowMotionFrames.decode(bytes).count, 2)
        let contact = XCTAttachment(data: try WorkflowMotionFrames.contactSheet(bytes), uniformTypeIdentifier: "public.png")
        contact.name = "Decoded native pointer journey GIF contact sheet"
        contact.lifetime = .keepAlways
        add(contact)
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
