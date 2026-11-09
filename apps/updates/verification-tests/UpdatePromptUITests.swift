import XCTest

final class UpdatePromptUITests: XCTestCase {
    func testPromptChoicesAcrossRestarts() {
        let run = UUID().uuidString
        let app = XCUIApplication()
        defer { app.terminate() }
        func action(_ title: String) -> XCUIElement {
            #if os(macOS)
            return app.windows.firstMatch.buttons[title]
            #else
            return app.buttons[title]
            #endif
        }
        func choose(_ title: String) {
            #if os(macOS)
            action(title).click()
            #else
            action(title).tap()
            #endif
        }
        func launch(_ version: String) {
            app.launchArguments = ["--run-id", run, "--version", version]
            app.launch()
        }
        launch("0.2.2")
        XCTAssertTrue(action("Update").waitForExistence(timeout: 10))
        XCTAssertTrue(action("Skip version").exists)
        let prompt = XCTAttachment(screenshot: app.screenshot())
        prompt.name = "Update prompt — isolated verification host"
        prompt.lifetime = .keepAlways
        add(prompt)
        choose("Not now")
        XCTAssertFalse(action("Update").exists)
        app.terminate()

        launch("0.2.2")
        XCTAssertTrue(action("Update").waitForExistence(timeout: 10))
        choose("Skip version")
        app.terminate()

        launch("0.2.2")
        XCTAssertFalse(action("Update").waitForExistence(timeout: 2))
        app.terminate()

        launch("0.2.3")
        XCTAssertTrue(action("Update").waitForExistence(timeout: 10))
        choose("Update")
        XCTAssertTrue(app.staticTexts["Update 0.2.3 selected. No software was changed."].waitForExistence(timeout: 5))
        app.terminate()
    }
}
