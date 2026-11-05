import ImageIO
import UIKit
import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testMarkerDwellOnlyForMoviesAndRetiresOnNextRun() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": "http://127.0.0.1:\(port)/projection"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let cases: [(String, [String]?, Bool)] = [
            ("no capture", nil, false), ("automatic PNG", ["screenshots"], false),
            ("explicit PNG", nil, true), ("GIF", ["gif"], false),
            ("video", ["video"], false), ("combined", ["screenshots", "gif", "video"], false)
        ]
        for (label, formats, explicit) in cases {
            var actions: [Body] = [["action": "click", "target": ["role": "button", "name": "Submit"]]]
            if explicit { actions.append(["action": "screenshot", "name": "explicit"]) }
            var script: Body = ["version": 1, "tabId": tab, "actions": actions,
                                "tapIndicator": ["color": "#00FF00", "radius": 25, "durationMs": 5000, "fade": false]]
            if let formats {
                script["capture"] = ["formats": formats, "fps": 5, "maxWidth": 384]
            }
            let start = ProcessInfo.processInfo.systemUptime
            let result = try await probe.call("kelpie_play_script", script)
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            XCTAssertEqual(result["success"] as? Bool, true, label)
            let movies = formats?.contains("gif") == true || formats?.contains("video") == true
            if movies {
                XCTAssertGreaterThan(elapsed, 4, label)
            } else {
                XCTAssertLessThan(elapsed, 4.5, label)
            }
            let artifacts = result["artifacts"] as? [Body] ?? []
            if explicit || formats?.contains("screenshots") == true {
                let pngs = artifacts.filter { $0["mimeType"] as? String == "image/png" }
                if explicit {
                    XCTAssertEqual(pngs.count, 1, label)
                    XCTAssertEqual(pngs.first?["actionIndex"] as? Int, 1, label)
                }
                let index = explicit ? 1 : 0
                let markerPNG = try XCTUnwrap(pngs.first { $0["actionIndex"] as? Int == index }, label)
                let bytes = try await probe.bytes(markerPNG, run: try XCTUnwrap(result["runId"] as? String))
                let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
                let frame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                XCTAssertTrue(WorkflowCaptureProbe.containsMarker(frame), label)
            }
            if let formats {
                let mimeTypes = Set(artifacts.compactMap { $0["mimeType"] as? String })
                if formats.contains("gif") { XCTAssertTrue(mimeTypes.contains("image/gif"), label) }
                if formats.contains("video") { XCTAssertTrue(mimeTypes.contains("video/mp4"), label) }
            }
            if label == "no capture" {
                let application = XCUIApplication()
                XCTAssertFalse(application.buttons["browser.recording.stop"].exists)
                let viewport = application.webViews.firstMatch
                let target = viewport.buttons["Submit"].firstMatch.frame.intersection(viewport.frame)
                let image = application.screenshot()
                let attachment = XCTAttachment(screenshot: image)
                attachment.name = "Non-movie marker after response"
                attachment.lifetime = .keepAlways
                add(attachment)
                XCTAssertTrue(WorkflowCaptureProbe.containsCenteredMarker(image, target: target, app: application.frame))
                let next = Task.detached { [probe] in
                    try await probe.request("/v1/play-script", [
                        "version": 1, "tabId": tab, "actions": [["action": "wait", "ms": 2000]]
                    ])
                }
                XCTAssertTrue(application.buttons["browser.recording.stop"].waitForExistence(timeout: 10))
                let duringNextRun = application.screenshot()
                XCTAssertFalse(WorkflowCaptureProbe.containsCenteredMarker(duringNextRun, target: target, app: application.frame))
                let nextResult = try await next.value
                XCTAssertEqual(nextResult["success"] as? Bool, true)
            }
        }
    }
    @MainActor
    func testRetiredMarkerDoesNotReappearAfterTabChange() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": "http://127.0.0.1:\(port)/projection"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let result = try await probe.call("kelpie_play_script", [
            "version": 1, "tabId": tab, "actions": [["action": "click", "target": ["role": "button", "name": "Submit"]]],
            "tapIndicator": ["color": "#00FF00", "radius": 25, "durationMs": 5000, "fade": false]
        ])
        XCTAssertEqual(result["success"] as? Bool, true)
        let application = XCUIApplication()
        let viewport = application.webViews.firstMatch
        let target = viewport.buttons["Submit"].firstMatch.frame.intersection(viewport.frame)
        XCTAssertTrue(WorkflowCaptureProbe.containsCenteredMarker(application.screenshot(), target: target, app: application.frame))
        let start = ProcessInfo.processInfo.systemUptime
        let created = try await probe.request("/v1/new-tab", ["url": "about:blank", "name": "retirement control"])
        let other = try XCTUnwrap(created["tabId"] as? String)
        let switched = try await probe.request("/v1/switch-tab", ["tabId": tab])
        XCTAssertEqual(switched["success"] as? Bool, true)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 4.5, "Tab control must occur before marker expiry")
        let restoredViewport = application.webViews.firstMatch
        let restoredButton = restoredViewport.buttons["Submit"].firstMatch
        XCTAssertTrue(restoredButton.waitForExistence(timeout: 2))
        let restoredTarget = restoredButton.frame.intersection(restoredViewport.frame)
        XCTAssertFalse(restoredTarget.isNull)
        XCTAssertFalse(WorkflowCaptureProbe.containsCenteredMarker(
            application.screenshot(), target: restoredTarget, app: application.frame
        ))
        _ = try await probe.request("/v1/close-tab", ["tabId": other])
    }

}
