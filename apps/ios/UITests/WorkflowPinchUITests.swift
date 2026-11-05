import ImageIO
import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testNativePinchClipsTapCenterAndExportedMarker() async throws {
        let initialOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = initialOrientation }
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
