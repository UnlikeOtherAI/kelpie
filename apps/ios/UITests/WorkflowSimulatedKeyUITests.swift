import UIKit
import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testIPadSimulatedKeyBeforeDuringAndAfterPlayback() async throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab,
            "actions": [["action": "navigate", "url": "http://127.0.0.1:\(port)/keyboard-control"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let application = XCUIApplication()
        let field = application.webViews.firstMatch.textFields["Keyboard test"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let focused = await waitForKeyboardEvents(fixture, path: "/keyboard-focused", count: 1)
        XCTAssertTrue(focused)
        application.typeKey(.return, modifierFlags: [])
        let initialEnter = await waitForKeyboardEvents(fixture, path: "/keyboard-enter", count: 1)
        let initialSubmit = await waitForKeyboardEvents(fixture, path: "/keyboard-submit", count: 1)
        XCTAssertTrue(initialEnter)
        XCTAssertTrue(initialSubmit)

        let playback = Task.detached { [probe] in
            try await probe.request("/v1/play-script", [
                "version": 1, "tabId": tab, "actions": [["action": "wait", "ms": 30000]]
            ])
        }
        addTeardownBlock { [probe] in _ = try? await probe.request("/v1/abort-script", [:]) }
        let stop = application.buttons["browser.recording.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15))
        let status = try await probe.request("/v1/get-script-status", [:])
        let activeRun = try XCTUnwrap(status["runId"] as? String)
        let before = fixture.requestCount(path: "/keyboard-enter")
        let beforeSubmit = fixture.requestCount(path: "/keyboard-submit")
        let focusBefore = fixture.requestCount(path: "/keyboard-focused")
        let blurBefore = fixture.requestCount(path: "/keyboard-unfocused")
        application.typeKey(.return, modifierFlags: [])
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let active = fixture.requestCount(path: "/keyboard-enter")
        let activeSubmit = fixture.requestCount(path: "/keyboard-submit")
        let blurActive = fixture.requestCount(path: "/keyboard-unfocused")
        stop.tap()
        let result = try await playback.value
        XCTAssertEqual(result["runId"] as? String, activeRun)
        XCTAssertEqual((result["error"] as? Body)?["code"] as? String, "SCRIPT_ABORTED")
        XCTAssertFalse(stop.exists)
        field.tap()
        application.typeKey(.return, modifierFlags: [])
        let afterEnter = await waitForKeyboardEvents(fixture, path: "/keyboard-enter", count: active + 1)
        let afterSubmit = await waitForKeyboardEvents(fixture, path: "/keyboard-submit", count: activeSubmit + 1)
        let facts: Body = [
            "route": "XCTest typeKey simulated iPad keyboard", "beforeEnter": before, "activeEnter": active,
            "afterEnter": fixture.requestCount(path: "/keyboard-enter"), "beforeSubmit": beforeSubmit,
            "activeSubmit": activeSubmit, "afterSubmit": fixture.requestCount(path: "/keyboard-submit"),
            "focusBefore": focusBefore, "blurBefore": blurBefore, "blurActive": blurActive,
            "sameRun": result["runId"] as? String == activeRun
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "Simulated iPad keyboard before during after"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(active, before, "Simulated Enter reached the focused page during playback")
        XCTAssertEqual(activeSubmit, beforeSubmit, "Simulated Enter submitted the page during playback")
        XCTAssertTrue(afterEnter, "Simulated Enter must work after playback")
        XCTAssertTrue(afterSubmit, "Simulated Enter must submit after playback")
    }

    private func waitForKeyboardEvents(_ fixture: WorkflowLoopbackPage, path: String, count: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if fixture.requestCount(path: path) >= count { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        } while Date() < deadline
        return false
    }
}
