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
        let compact = UIDevice.current.userInterfaceIdiom == .phone || app.frame.width < 600
        let shortcut = app.buttons["browser.snapshot-3d.button"]
        let menuItem = app.buttons["browser.snapshot-3d.menu"]
        if compact {
            XCTAssertFalse(shortcut.exists)
            XCTAssertFalse(app.buttons["browser.account"].exists)
            more.tap()
            XCTAssertTrue(app.buttons["Network inspector"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["browser.account.menu"].exists || app.buttons["Cancel login"].exists)
            XCTAssertTrue(menuItem.exists)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.18)).tap()
        } else {
            XCTAssertTrue(shortcut.exists)
            XCTAssertLessThanOrEqual(shortcut.frame.maxX, more.frame.minX)
        }

        func toggleInspector() {
            if compact {
                more.tap()
                menuItem.tap()
            } else {
                shortcut.tap()
            }
        }

        for _ in 0..<2 {
            if !compact { XCTAssertEqual(shortcut.value as? String, "Off") }
            toggleInspector()
            let exit = app.buttons["browser.snapshot3d.exit"]
            XCTAssertTrue(exit.waitForExistence(timeout: 10))
            if !compact { XCTAssertEqual(shortcut.value as? String, "On") }
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
            toggleInspector()
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
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        let compact = UIDevice.current.userInterfaceIdiom == .phone || app.frame.width < 600
        let inspector = app.buttons[compact ? "browser.snapshot-3d.menu" : "browser.snapshot-3d.button"]

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
        if compact { more.tap() }
        XCTAssertTrue(inspector.waitForNonExistence(timeout: 5))
        if compact { app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.18)).tap() }
        setInspectorEnabled(true)
        if compact { more.tap() }
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
    }
}
