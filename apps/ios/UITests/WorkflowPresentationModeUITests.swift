import UIKit
import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testScriptStopPreservesNonMovieViewportAndMovieImmersion() async throws {
        let (fixture, tab) = try await ready()
        continueAfterFailure = true
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": "http://127.0.0.1:\(port)/projection"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let modes: [(String, [String]?, Bool, Bool)] = [
            ("No capture", nil, false, false), ("Automatic PNG", ["screenshots"], false, false),
            ("Explicit PNG", nil, true, false), ("GIF", ["gif"], false, true),
            ("Video", ["video"], false, true)
        ]
        let application = XCUIApplication()
        for (name, formats, explicit, movie) in modes {
            let viewport = application.webViews.firstMatch
            let initial = viewport.frame
            var actions: [Body] = [["action": "wait", "ms": 5000]]
            if explicit { actions.append(["action": "screenshot", "name": "still"]) }
            var script: Body = ["version": 1, "tabId": tab, "actions": actions]
            if let formats { script["capture"] = ["formats": formats, "fps": 5, "maxWidth": 384] }
            let playback = Task.detached { [probe] in try await probe.request("/v1/play-script", script) }
            let stop = application.buttons["browser.recording.stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 15), name)
            let during = viewport.frame
            let chrome = application.buttons["browser.more"]
            if movie {
                XCTAssertFalse(chrome.exists, name)
            } else {
                XCTAssertTrue(chrome.exists, name)
                XCTAssertFalse(chrome.isHittable, name)
                XCTAssertEqual(during.minX, initial.minX, accuracy: 0.5, name)
                XCTAssertEqual(during.minY, initial.minY, accuracy: 0.5, name)
                XCTAssertEqual(during.width, initial.width, accuracy: 0.5, name)
                XCTAssertEqual(during.height, initial.height, accuracy: 0.5, name)
            }
            let attachment = XCTAttachment(screenshot: application.screenshot())
            attachment.name = name + " active script and Stop"
            attachment.lifetime = .keepAlways
            add(attachment)
            if name == "No capture" { stop.tap() }
            let result = try await playback.value
            if name == "No capture" {
                XCTAssertEqual((result["error"] as? Body)?["code"] as? String, "SCRIPT_ABORTED")
            } else {
                XCTAssertEqual(result["success"] as? Bool, true, name)
            }
            XCTAssertFalse(stop.exists, name)
            if !movie {
                let after = viewport.frame
                XCTAssertEqual(after.minX, initial.minX, accuracy: 0.5, name)
                XCTAssertEqual(after.minY, initial.minY, accuracy: 0.5, name)
                XCTAssertEqual(after.width, initial.width, accuracy: 0.5, name)
                XCTAssertEqual(after.height, initial.height, accuracy: 0.5, name)
            }
        }
    }
}
