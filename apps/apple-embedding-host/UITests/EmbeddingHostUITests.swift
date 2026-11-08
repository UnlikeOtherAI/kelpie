import XCTest

final class EmbeddingHostUITests: XCTestCase {
    @MainActor
    func testCompleteBrowserMovesWithoutLosingTabs() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hideWelcomeCard", "YES", "-sessionTabURLs", "()", "-homeURL", "about:blank"]
        app.launch()
        app.buttons["Open browser"].tap()
        let field = addressField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        navigate("First embedded page", app)
        XCTAssertTrue(app.webViews.staticTexts["First embedded page"].waitForExistence(timeout: 15))

        app.buttons["browser.tabs.add"].tap()
        navigate("Second embedded page", app)
        XCTAssertTrue(app.webViews.staticTexts["Second embedded page"].waitForExistence(timeout: 15))
        capture("embedded-two-tabs", app)
        app.buttons["Move browser"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Second embedded page"].waitForExistence(timeout: 10))
        capture("embedded-moved", app)

        app.buttons["browser.account"].tap()
        XCTAssertTrue(app.staticTexts["Host sign-in requested"].waitForExistence(timeout: 5))
        app.buttons["Move browser"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Second embedded page"].waitForExistence(timeout: 10))
        app.buttons["Close browser"].tap()
        XCTAssertTrue(app.staticTexts["Browser detached; host remains open"].waitForExistence(timeout: 5))
        XCTAssertFalse(addressField(app).exists)
        capture("embedded-detached", app)
        app.buttons["Open browser"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Second embedded page"].waitForExistence(timeout: 10))
        app.terminate()
    }

    @MainActor
    private func addressField(_ app: XCUIApplication) -> XCUIElement {
        #if os(macOS)
        return app.textFields["Search or enter website name"]
        #else
        return app.textFields["browser.url.field"]
        #endif
    }

    @MainActor
    private func navigate(_ title: String, _ app: XCUIApplication) {
        let html = "<meta name=\"viewport\" content=\"width=device-width\"><title>\(title)</title><h1>\(title)</h1>"
        let url = "data:text/html;base64," + Data(html.utf8).base64EncodedString()
        let field = addressField(app)
        field.tap()
        #if os(macOS)
        field.typeKey("a", modifierFlags: .command)
        #else
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let initial = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: initial.count))
        #endif
        field.typeText(url + "\n")
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
