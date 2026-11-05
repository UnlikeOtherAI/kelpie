import ImageIO
import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testNativePinchClipsTapCenterAndInvalidatesPointerTarget() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let origin = "http://127.0.0.1:" + String(try XCTUnwrap(fixture.listener.port?.rawValue))
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": origin + "/pinch"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let viewport = XCUIApplication().webViews.firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let initial = try await pinchMetrics(tab, selector: "#zoom")
        let initialScale = try XCTUnwrap(initial["scale"] as? Double)

        // This drives WebKit's native pinch recognizer. The fixture reports the resulting visual viewport.
        viewport.pinch(withScale: 2, velocity: 1)
        let deadline = Date().addingTimeInterval(5)
        var zoomed = try await pinchMetrics(tab, selector: "#zoom")
        while (zoomed["scale"] as? Double ?? 0) < initialScale * 1.3, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
            zoomed = try await pinchMetrics(tab, selector: "#zoom")
        }
        XCTAssertGreaterThan(try XCTUnwrap(zoomed["scale"] as? Double), initialScale * 1.3)
        XCTAssertLessThan(try XCTUnwrap(zoomed["width"] as? Double), try XCTUnwrap(zoomed["layoutWidth"] as? Double))
        let pinch = XCTAttachment(screenshot: viewport.screenshot())
        pinch.name = "Actual native pinch before the partially visible Edge button tap"
        pinch.lifetime = .keepAlways
        add(pinch)

        let tapped = try await probe.call("kelpie_play_script", [
            "version": 1, "tabId": tab,
            "actions": [
                ["action": "tap", "target": ["role": "button", "name": "Edge"]],
                ["action": "extract", "name": "geometry", "params": [
                    "fields": [["name": "clicked", "selector": "#clicked", "source": "text"]]
                ]]
            ],
            "tapIndicator": ["color": "#00FF00", "radius": 20, "durationMs": 300, "wobble": false],
            "capture": ["formats": ["screenshots"], "maxWidth": 384]
        ])
        XCTAssertEqual(tapped["success"] as? Bool, true, "\(tapped["error"] ?? "")")
        let extracted = try XCTUnwrap((tapped["outputs"] as? Body)?["geometry"] as? Body)
        let click = try pinchValue(extracted)
        XCTAssertEqual(try XCTUnwrap(click["clickX"] as? Double), try XCTUnwrap(click["expectedX"] as? Double), accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(click["clickY"] as? Double), try XCTUnwrap(click["expectedY"] as? Double), accuracy: 1)
        XCTAssertGreaterThan(try XCTUnwrap(click["visibleWidth"] as? Double), 10)
        XCTAssertLessThan(try XCTUnwrap(click["visibleWidth"] as? Double), try XCTUnwrap(click["buttonWidth"] as? Double) - 20)
        let manifest = try XCTUnwrap((tapped["artifacts"] as? [Body])?.first { $0["actionIndex"] as? Int == 0 })
        let data = try await probe.bytes(manifest, run: try XCTUnwrap(tapped["runId"] as? String))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "Pinched viewport step PNG with clipped-center marker"
        attachment.lifetime = .keepAlways
        add(attachment)
        let geometry = XCTAttachment(data: try JSONSerialization.data(withJSONObject: click, options: [.sortedKeys]),
                                     uniformTypeIdentifier: "public.json")
        geometry.name = "Actual visual viewport and clicked center"
        geometry.lifetime = .keepAlways
        add(geometry)
        try verifyPinchMarker(data, click: click)

        let before = try await pinchMetrics(tab, selector: "#zoom")
        let neutral = try XCTUnwrap(viewport.screenshot().image.cgImage)
        XCTAssertNil(try WorkflowMotionFrames.measure(neutral, time: 0).pointer, "Neutral fixture must contain no white pointer")
        let playback = Task.detached { [probe] in
            try await probe.request("/v1/play-script", [
                "version": 1, "tabId": tab,
                "actions": [["action": "tap", "target": ["role": "button", "name": "Edge"]]],
                "pointer": ["enabled": true, "curve": "c", "durationMs": 5000]
            ])
        }
        XCTAssertTrue(XCUIApplication().buttons["browser.recording.stop"].waitForExistence(timeout: 5))
        let pointerDeadline = Date().addingTimeInterval(3)
        var observedPointer = false
        repeat {
            let screen = viewport.screenshot()
            if let image = screen.image.cgImage, try WorkflowMotionFrames.measure(image, time: 0).pointer != nil {
                let evidence = XCTAttachment(screenshot: screen)
                evidence.name = "Native pointer is moving before the second pinch"
                evidence.lifetime = .keepAlways
                add(evidence)
                observedPointer = true
                break
            }
            try await Task.sleep(nanoseconds: 60_000_000)
        } while Date() < pointerDeadline
        XCTAssertTrue(observedPointer, "A displayed pointer proves target resolution preceded the second pinch")
        viewport.pinch(withScale: 1.4, velocity: 1)
        let refused = try await playback.value
        XCTAssertEqual(refused["success"] as? Bool, false)
        let code = try XCTUnwrap((refused["error"] as? Body)?["code"] as? String)
        XCTAssertTrue(["VIEWPORT_CHANGED", "STALE_TARGET"].contains(code), code)
        XCTAssertEqual(refused["actionsExecuted"] as? Int, 0)
        XCTAssertEqual(refused["mayHaveCompleted"] as? Bool ?? false, false)
        let after = try await pinchMetrics(tab, selector: "#zoom")
        XCTAssertGreaterThan(try XCTUnwrap(after["scale"] as? Double), try XCTUnwrap(before["scale"] as? Double) + 0.1)
        XCTAssertEqual(after["clicks"] as? Int, 1)
        let final = XCTAttachment(data: try JSONSerialization.data(withJSONObject: after, options: [.sortedKeys]),
                                 uniformTypeIdentifier: "public.json")
        final.name = "Changed native viewport with zero additional clicks"
        final.lifetime = .keepAlways
        add(final)
    }

    private func pinchValue(_ extracted: Body) throws -> Body {
        let text = try XCTUnwrap(((extracted["fields"] as? [Body])?.first?["values"] as? [String])?.first)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? Body)
    }

    private func pinchMetrics(_ tab: String, selector: String) async throws -> Body {
        let response = try await probe.request("/v1/browser-control", [
            "version": 1, "tabId": tab, "method": "tab.extract",
            "params": ["fields": [["name": "metrics", "selector": selector, "source": "text"]]]
        ])
        XCTAssertEqual(response["ok"] as? Bool, true)
        return try pinchValue(XCTUnwrap(response["value"] as? Body))
    }

    private func verifyPinchMarker(_ png: Data, click: Body) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let x = (try XCTUnwrap(click["expectedX"] as? Double) - XCTUnwrap(click["x"] as? Double)) /
            (try XCTUnwrap(click["width"] as? Double)) * Double(image.width)
        let y = (try XCTUnwrap(click["expectedY"] as? Double) - XCTUnwrap(click["y"] as? Double)) /
            (try XCTUnwrap(click["height"] as? Double)) * Double(image.height)
        let center = try XCTUnwrap(image.cropping(to: CGRect(x: x - 6, y: y - 6, width: 12, height: 12).integral))
        XCTAssertTrue(WorkflowCaptureProbe.containsMarker(center, minimumCoverage: 0.12))
    }
}
