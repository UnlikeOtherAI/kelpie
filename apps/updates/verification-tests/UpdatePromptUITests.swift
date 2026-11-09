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
        func attachScreenshot(_ name: String) {
            #if os(macOS)
            let screenshot = app.windows.firstMatch.screenshot()
            #else
            let screenshot = app.screenshot()
            #endif
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        func launch(_ version: String) {
            app.launchArguments = ["--run-id", run, "--version", version]
            app.launch()
        }
        launch("0.2.2")
        XCTAssertTrue(action("Update").waitForExistence(timeout: 10))
        XCTAssertTrue(action("Skip version").exists)
        attachScreenshot("Update prompt — isolated verification host")
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
        XCTAssertTrue(app.staticTexts["Downloading and verifying update… Kelpie will restart when ready."].exists)
        attachScreenshot("Update progress — simulated verification host")
        app.terminate()
    }
}
