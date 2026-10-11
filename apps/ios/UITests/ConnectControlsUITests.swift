import XCTest

final class ConnectControlsUITests: XCTestCase {
    @MainActor
    func testConnectionStatusHasSettingsDoorway() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hideWelcomeCard", "YES", "-sessionTabURLs", "()", "-homeURL", "about:blank"]
        app.launch()
        let more = app.descendants(matching: .any)["browser.menu.fab"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        let settings = app.buttons["browser.menu.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.staticTexts["Nessie"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Signed out"].exists)
        XCTAssertFalse(app.buttons["nessie.pause"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "nessie-settings-signed-out"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
