import XCTest

final class AddressSearchUITests: XCTestCase {
    @MainActor
    func testBareWordOpensGoogleSearch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hideWelcomeCard", "YES", "-sessionTabURLs", "()", "-homeURL", "about:blank"]
        app.launch()
        let field = app.textFields["browser.url.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // The short fixture URL ends before the right edge of the editable field.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let initial = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: initial.count))
        field.typeText("GitHub\n")
        let navigated = NSPredicate(format: "value BEGINSWITH %@", "https://www.google.com/search?q=GitHub")
        expectation(for: navigated, evaluatedWith: field)
        waitForExpectations(timeout: 20)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "address-search-google"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
