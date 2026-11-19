import XCTest

final class Snapshot3DUITests: XCTestCase {
    @MainActor
    func testEnterControlsExitAndReenter() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let html = "<title>3D fixture</title><main><h1>Inspect me</h1><p>Nested content</p></main>"
        let url = "data:text/html;base64," + Data(html.utf8).base64EncodedString()
        app.launchArguments = [
            "-hideWelcomeCard", "YES", "-sessionTabURLs", "()", "-homeURL", url,
            "-enable3DInspector", "YES"
        ]
        app.launch()
        let more = app.buttons["browser.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        let inspector = app.buttons["browser.snapshot-3d.button"]
        XCTAssertTrue(inspector.exists)
        XCTAssertLessThanOrEqual(inspector.frame.maxX, more.frame.minX)
        more.tap()
        XCTAssertTrue(app.buttons["Network inspector"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", "3D inspector", "browser.snapshot-3d.button")
        ).firstMatch.exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.18)).tap()
        for _ in 0..<2 {
            XCTAssertEqual(inspector.value as? String, "Off")
            inspector.tap()
            let exit = app.buttons["browser.snapshot3d.exit"]
            XCTAssertTrue(exit.waitForExistence(timeout: 10))
            XCTAssertEqual(inspector.value as? String, "On")
            let page = app.webViews.firstMatch
            let pan = page.descendants(matching: .any).matching(identifier: "Pan 3D view").firstMatch
            XCTAssertTrue(pan.waitForExistence(timeout: 5))
            pan.tap()
            page.buttons["Move page up without zooming"].tap()
            page.buttons["Move page down without zooming"].tap()
            page.buttons["Front view (Z axis)"].tap()
            XCTAssertTrue(page.images["Snapshot of the inspected website"].exists)
            page.buttons["Open element toolbox"].tap()
            XCTAssertTrue(page.buttons["Close element toolbox"].waitForExistence(timeout: 5))
            let evidence = XCTAttachment(screenshot: app.screenshot())
            evidence.name = "3D toolbox and orientation preview"
            evidence.lifetime = .keepAlways
            add(evidence)
            page.buttons["Close element toolbox"].tap()
            app.buttons["browser.snapshot3d.zoom-in"].tap()
            app.buttons["browser.snapshot3d.zoom-out"].tap()
            app.buttons["browser.snapshot3d.reset"].tap()
            inspector.tap()
            XCTAssertTrue(exit.waitForNonExistence(timeout: 5))
            XCTAssertEqual(app.state, .runningForeground)
        }
    }

    @MainActor
    func testDisabledInspectorIsAbsent() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchArguments = ["-hideWelcomeCard", "YES"]
        app.launch()
        let more = app.buttons["browser.more"]
        let inspector = app.buttons["browser.snapshot-3d.button"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))

        func setInspectorEnabled(_ enabled: Bool) {
            more.tap()
            app.buttons["Settings"].tap()
            let setting = app.switches["3D DOM Inspector"]
            for _ in 0..<5 where !setting.isHittable { app.swipeUp() }
            XCTAssertTrue(setting.isHittable)
            if (setting.value as? String == "1") != enabled {
                setting.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            XCTAssertEqual(setting.value as? String, enabled ? "1" : "0")
            app.buttons["Done"].tap()
        }

        setInspectorEnabled(false)
        XCTAssertTrue(inspector.waitForNonExistence(timeout: 5))
        setInspectorEnabled(true)
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
    }
}
