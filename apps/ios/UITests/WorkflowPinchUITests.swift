import ImageIO
import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testNativePinchClipsTapCenterAndExportedMarker() async throws {
        let initialOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = initialOrientation }
        testLaunchArguments.append("--test-pinch-projection")
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let origin = "http://127.0.0.1:" + String(try XCTUnwrap(fixture.listener.port?.rawValue))
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": origin + "/pinch?case=visible"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let viewport = XCUIApplication().webViews.firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let initial = try await pinchMetrics(tab, selector: "#zoom")
        let initialNative = await nativeZoomEvidence()
        let initialScale = try XCTUnwrap(initial["scale"] as? Double)

        // This drives WebKit's native pinch recognizer. The fixture reports the resulting visual viewport.
        viewport.pinch(withScale: 2, velocity: 1)
        let deadline = Date().addingTimeInterval(5)
        var zoomed = try await pinchMetrics(tab, selector: "#zoom")
        while (zoomed["scale"] as? Double ?? 0) < initialScale * 1.3, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
            zoomed = try await pinchMetrics(tab, selector: "#zoom")
        }
        let pinch = XCTAttachment(screenshot: viewport.screenshot())
        pinch.name = "Actual native pinch before the partially visible Edge button tap"
        pinch.lifetime = .keepAlways
        add(pinch)
        let zoomedNative = await nativeZoomEvidence()
        let metrics = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
            "initial": initial, "zoomed": zoomed, "nativeBefore": initialNative, "nativeAfter": zoomedNative
        ],
                                                                     options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        metrics.name = "Native pinch viewport metrics before assertions"
        metrics.lifetime = .keepAlways
        add(metrics)
        XCTAssertGreaterThan(try XCTUnwrap(zoomed["scale"] as? Double), initialScale * 1.3)
        // WebKit can report innerWidth equal to the zoomed visual width; compare the
        // same visual viewport before and after the actual gesture instead.
        XCTAssertLessThan(try XCTUnwrap(zoomed["width"] as? Double), try XCTUnwrap(initial["width"] as? Double))
        XCTAssertEqual(zoomed["hitEdge"] as? Bool, true, "Calibrated intersection must be hit-testable")
        XCTAssertGreaterThan(try XCTUnwrap(zoomed["visibleWidth"] as? Double), 10)
        XCTAssertLessThan(try XCTUnwrap(zoomed["visibleWidth"] as? Double), try XCTUnwrap(zoomed["edgeWidth"] as? Double) - 20)
        XCTAssertGreaterThan(try XCTUnwrap(zoomed["visibleHeight"] as? Double), 10)
        try await Task.sleep(nanoseconds: 100_000_000)
        let settled = try await pinchMetrics(tab, selector: "#zoom")
        for key in ["x", "y", "width", "height", "scale", "edgeLeft", "edgeTop", "edgeWidth", "edgeHeight", "visibleWidth", "visibleHeight"] {
            XCTAssertEqual(try XCTUnwrap(settled[key] as? Double), try XCTUnwrap(zoomed[key] as? Double), accuracy: 0.1, key)
        }

        let envelope = try await probe.toolEnvelope("kelpie_extension", ["name": "kelpie_play_script", "arguments": [
            "version": 1, "tabId": tab,
            "actions": [
                ["action": "tap", "target": ["role": "button", "name": "Edge"]],
                ["action": "extract", "name": "geometry", "params": [
                    "fields": [["name": "clicked", "selector": "#clicked", "source": "text"]]
                ]]
            ],
            "tapIndicator": ["color": "#00FF00", "radius": 20, "durationMs": 300, "wobble": false],
            "capture": ["formats": ["screenshots"], "maxWidth": 384]
        ]])
        if envelope["ok"] as? Bool != true {
            let after = try await pinchMetrics(tab, selector: "#zoom")
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
                "beforePlay": zoomed, "afterPlay": after
            ], options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
            attachment.name = "Pinch viewport immediately before and after rejected play"
            attachment.lifetime = .keepAlways
            add(attachment)
            let status = try await probe.toolEnvelope("kelpie_get_script_status", [:])
            let error = ((status["value"] as? Body)?["runError"] as? Body) ?? [:]
            XCTFail("MCP play failed; terminal code: " + WorkflowCaptureProbe.errorCode(["error": error]))
            return
        }
        let tapped = try XCTUnwrap(envelope["value"] as? Body)
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
        let diagnostics = try await probe.request("/v1/debug-screens", [:])
        let evidence = try XCTUnwrap(diagnostics["testCaptureEvidence"] as? Body)
        XCTAssertEqual(evidence["runId"] as? String, tapped["runId"] as? String)
        let artifacts = try XCTUnwrap(evidence["artifacts"] as? Body)
        let facts = try XCTUnwrap(artifacts[try XCTUnwrap(manifest["id"] as? String)] as? Body)
        try verifyPinchMarker(data, click: click, facts: facts)

    }

    @MainActor
    func testNativePinchRejectsClippedUnhittableTarget() async throws {
        let initialOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = initialOrientation }
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab,
            "actions": [["action": "navigate", "url": "http://127.0.0.1:\(port)/pinch"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let viewport = XCUIApplication().webViews.firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let initial = try await pinchMetrics(tab, selector: "#zoom")
        viewport.pinch(withScale: 2, velocity: 1)
        let deadline = Date().addingTimeInterval(5)
        var zoomed = try await pinchMetrics(tab, selector: "#zoom")
        while (zoomed["scale"] as? Double ?? 0) < (initial["scale"] as? Double ?? 1) * 1.3,
              Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
            zoomed = try await pinchMetrics(tab, selector: "#zoom")
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: zoomed, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "Unhittable pinch target before refusal"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(try XCTUnwrap(zoomed["scale"] as? Double), try XCTUnwrap(initial["scale"] as? Double) * 1.3)
        XCTAssertGreaterThan(try XCTUnwrap(zoomed["visibleWidth"] as? Double), 10)
        XCTAssertEqual(zoomed["hitEdge"] as? Bool, false)
        let envelope = try await probe.toolEnvelope("kelpie_extension", ["name": "kelpie_play_script", "arguments": [
            "version": 1, "tabId": tab, "actions": [["action": "tap", "target": ["role": "button", "name": "Edge"]]]
        ]])
        XCTAssertEqual(envelope["ok"] as? Bool, false)
        let status = try await probe.toolEnvelope("kelpie_get_script_status", [:])
        let error = ((status["value"] as? Body)?["runError"] as? Body) ?? [:]
        XCTAssertEqual(WorkflowCaptureProbe.errorCode(["error": error]), "TARGET_NOT_FOUND")
        let after = try await pinchMetrics(tab, selector: "#zoom")
        XCTAssertEqual(after["clicks"] as? Int, 0)
    }

    @MainActor
    func testNativePinchScrollableControl() async throws {
        let initialOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = initialOrientation }
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": "http://127.0.0.1:\(port)/pinch-scroll"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let viewport = XCUIApplication().webViews.firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let initial = try await pinchMetrics(tab, selector: "#zoom")
        let initialNative = await nativeZoomEvidence()
        viewport.pinch(withScale: 2, velocity: 1)
        let deadline = Date().addingTimeInterval(5)
        var zoomed = try await pinchMetrics(tab, selector: "#zoom")
        while (zoomed["scale"] as? Double ?? 0) < (initial["scale"] as? Double ?? 1) * 1.3, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
            zoomed = try await pinchMetrics(tab, selector: "#zoom")
        }
        let zoomedNative = await nativeZoomEvidence()
        let evidence = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
            "initial": initial, "zoomed": zoomed, "nativeBefore": initialNative, "nativeAfter": zoomedNative
        ], options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        evidence.name = "Scrollable native pinch control metrics"
        evidence.lifetime = .keepAlways
        add(evidence)
        let image = XCTAttachment(screenshot: viewport.screenshot())
        image.name = "Scrollable native pinch control"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertGreaterThan(try XCTUnwrap(zoomed["scale"] as? Double), (initial["scale"] as? Double ?? 1) * 1.3)
    }

    private func nativeZoomEvidence() async -> Body {
        guard let value = try? await probe.request("/v1/debug-screens", [:]),
              let webView = value["webView"] as? Body, let scroll = webView["scrollView"] as? Body else { return [:] }
        var result: Body = [:]
        if let zoom = scroll["zoomScale"] as? Double, zoom.isFinite { result["scrollZoomScale"] = zoom }
        if let zoom = webView["pageZoom"] as? Double, zoom.isFinite { result["pageZoom"] = zoom }
        if let pinch = scroll["pinch"] as? Body {
            for key in ["available", "enabled", "scrollEnabled"] {
                if let value = pinch[key] as? Bool { result[key] = value }
            }
            for key in ["state", "minimumScale", "maximumScale"] {
                if let value = pinch[key] as? Double, value.isFinite { result[key] = value }
            }
        }
        return result
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

    private func verifyPinchMarker(_ png: Data, click: Body, facts: Body) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let projection = try XCTUnwrap(facts["projection"] as? Body)
        func number(_ key: String) throws -> Double {
            let value = try XCTUnwrap(projection[key] as? Double)
            XCTAssertTrue(value.isFinite)
            return value
        }
        let nativeWidth = try number("nativeWidth"), nativeHeight = try number("nativeHeight")
        let contentX = try number("contentX"), contentY = try number("contentY")
        let contentWidth = try number("contentWidth"), contentHeight = try number("contentHeight")
        let visualX = try number("visualX"), visualY = try number("visualY")
        let visualWidth = try number("visualWidth"), visualHeight = try number("visualHeight")
        XCTAssertGreaterThan(nativeWidth, 0)
        XCTAssertGreaterThan(nativeHeight, 0)
        XCTAssertGreaterThan(contentWidth, 0)
        XCTAssertGreaterThan(contentHeight, 0)
        XCTAssertGreaterThan(visualWidth, 0)
        XCTAssertGreaterThan(visualHeight, 0)
        XCTAssertEqual(visualX, try XCTUnwrap(click["x"] as? Double), accuracy: 0.01)
        XCTAssertEqual(visualY, try XCTUnwrap(click["y"] as? Double), accuracy: 0.01)
        XCTAssertEqual(visualWidth, try XCTUnwrap(click["width"] as? Double), accuracy: 0.01)
        XCTAssertEqual(visualHeight, try XCTUnwrap(click["height"] as? Double), accuracy: 0.01)
        XCTAssertEqual(try number("scale"), try XCTUnwrap(click["scale"] as? Double), accuracy: 0.01)
        let x = (contentX + (try XCTUnwrap(click["expectedX"] as? Double) - visualX) * contentWidth / visualWidth) *
            Double(image.width) / nativeWidth
        let y = (contentY + (try XCTUnwrap(click["expectedY"] as? Double) - visualY) * contentHeight / visualHeight) *
            Double(image.height) / nativeHeight
        let center = try XCTUnwrap(image.cropping(to: CGRect(x: x - 6, y: y - 6, width: 12, height: 12).integral))
        XCTAssertTrue(WorkflowCaptureProbe.containsMarker(center, minimumCoverage: 0.12))
    }
}
