import XCTest

final class UpdatePromptUITests: XCTestCase {
    func testPromptChoicesAcrossRestarts() {
        let run = UUID().uuidString
        let app = XCUIApplication()
        func launch(_ version: String) {
            app.launchArguments = ["--run-id", run, "--version", version]
            app.launch()
        }
        launch("0.2.2")
        XCTAssertTrue(app.buttons["Update"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Skip version"].exists)
        let prompt = XCTAttachment(screenshot: app.screenshot())
        prompt.name = "Update prompt — isolated verification host"
        prompt.lifetime = .keepAlways
        add(prompt)
        app.buttons["Not now"].tap()
        XCTAssertFalse(app.buttons["Update"].exists)
        app.terminate()

        launch("0.2.2")
        XCTAssertTrue(app.buttons["Update"].waitForExistence(timeout: 10))
        app.buttons["Skip version"].tap()
        app.terminate()

        launch("0.2.2")
        XCTAssertFalse(app.buttons["Update"].waitForExistence(timeout: 2))
        app.terminate()

        launch("0.2.3")
        XCTAssertTrue(app.buttons["Update"].waitForExistence(timeout: 10))
        app.buttons["Update"].tap()
        XCTAssertTrue(app.staticTexts["Update 0.2.3 selected. No software was changed."].waitForExistence(timeout: 5))
        app.terminate()
    }
}
