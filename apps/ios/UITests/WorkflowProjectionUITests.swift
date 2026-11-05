import UIKit
import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testLiveMarkerProjectionMatchesSameSceneTarget() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": "http://127.0.0.1:\(port)/projection"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let actions: [Body] = [
            ["action": "wait", "ms": 1200],
            ["action": "click", "target": ["role": "button", "name": "Submit"]],
            ["action": "extract", "name": "geometry", "params": [
                "fields": [["name": "center", "selector": "#geometry", "source": "text"]]
            ]]
        ]
        let script: Body = [
            "version": 1, "tabId": tab, "actions": actions,
            "tapIndicator": ["color": "#00FF00", "radius": 25, "durationMs": 4000, "wobble": false, "fade": false]
        ]
        let playback = Task.detached { [probe] in try await probe.request("/v1/play-script", script) }
        let application = XCUIApplication()
        XCTAssertTrue(application.buttons["browser.recording.stop"].waitForExistence(timeout: 15))
        try await Task.sleep(nanoseconds: 2_000_000_000)
        // Snapshot before the potentially slow accessibility hierarchy queries.
        let screen = application.screenshot()
        let viewport = application.webViews.firstMatch
        let button = viewport.buttons["Submit"].firstMatch
        let visibleTarget = button.frame.intersection(viewport.frame)
        let screenshot = XCTAttachment(screenshot: screen)
        screenshot.name = "Same-scene native marker and accessible target"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let result = try await playback.value
        XCTAssertEqual(result["success"] as? Bool, true, WorkflowCaptureProbe.errorCode(result))
        let geometry = try XCTUnwrap((result["outputs"] as? Body)?["geometry"] as? Body)
        let text = try XCTUnwrap(((geometry["fields"] as? [Body])?.first?["values"] as? [String])?.first)
        let click = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? Body)
        let native: Body = [
            "target": ["x": visibleTarget.minX, "y": visibleTarget.minY,
                       "width": visibleTarget.width, "height": visibleTarget.height],
            "webView": ["x": viewport.frame.minX, "y": viewport.frame.minY,
                        "width": viewport.frame.width, "height": viewport.frame.height],
            "window": ["x": application.frame.minX, "y": application.frame.minY,
                       "width": application.frame.width, "height": application.frame.height],
            "click": click
        ]
        let evidence = XCTAttachment(data: try JSONSerialization.data(withJSONObject: native, options: [.sortedKeys]),
                                     uniformTypeIdentifier: "public.json")
        evidence.name = "Same-scene CSS click and native accessibility frames"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertEqual(click["centered"] as? Bool, true)
        XCTAssertFalse(visibleTarget.isNull)
        XCTAssertTrue(WorkflowCaptureProbe.containsCenteredMarker(screen, target: visibleTarget, app: application.frame),
                      "The live marker must meet the same-scene accessible target")
    }
}
