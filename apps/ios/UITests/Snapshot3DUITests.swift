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
        for _ in 0..<2 {
            more.tap()
            app.buttons["3D inspector"].tap()
            let exit = app.buttons["browser.snapshot3d.exit"]
            XCTAssertTrue(exit.waitForExistence(timeout: 10))
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
            exit.tap()
            XCTAssertTrue(exit.waitForNonExistence(timeout: 5))
            XCTAssertEqual(app.state, .runningForeground)
        }
    }
}
