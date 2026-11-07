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
        let enter = app.buttons["browser.snapshot-3d.button"]
        XCTAssertTrue(enter.waitForExistence(timeout: 15))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<2 {
            enter.tap()
            let exit = app.buttons["browser.snapshot3d.exit"]
            XCTAssertTrue(exit.waitForExistence(timeout: 10))
            app.buttons["browser.snapshot3d.zoom-in"].tap()
            app.buttons["browser.snapshot3d.zoom-out"].tap()
            app.buttons["browser.snapshot3d.reset"].tap()
            exit.tap()
            XCTAssertTrue(exit.waitForNonExistence(timeout: 5))
            XCTAssertEqual(app.state, .runningForeground)
        }
    }
}
