import XCTest

final class BrowserChromeUITests: XCTestCase {
    @MainActor
    func testNativeChromeJourney() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let html = """
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Chrome fixture</title>
        <style>body{margin:0;background:#dce8fc;color:#142240;font:24px system-ui}
        header{padding:32px;background:#dce8fc}section{height:2000px;padding:32px;
        background:linear-gradient(#dce8fc,#20314d);color:white}</style>
        <header>Browser chrome fixture</header><section>Scroll this page</section>
        """
        let url = "data:text/html;base64," + Data(html.utf8).base64EncodedString()
        app.launchArguments = ["-hideWelcomeCard", "YES", "-sessionTabURLs", "()", "-homeURL", url]
        app.launch()
        let field = app.textFields["browser.url.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        let tablet = app.windows.firstMatch.frame.width > 600
        if tablet { XCUIDevice.shared.orientation = .landscapeLeft }
        capture("expanded", app)

        app.webViews.firstMatch.swipeUp()
        let collapsed = app.buttons["browser.bottom-bar.collapsed"]
        XCTAssertTrue(collapsed.waitForExistence(timeout: 5))
        if tablet { XCTAssertTrue(app.buttons["browser.tabs.add"].exists) }
        capture("collapsed", app)
        collapsed.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThan(field.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        capture("keyboard", app)
        app.buttons["Cancel"].tap()

        app.buttons["browser.more"].tap()
        app.buttons["browser.tabs.add"].lastMatch.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let start = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -140)))
        let overview = app.otherElements["browser.tabs.overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 Tabs"].exists)
        capture("overview", app)

        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.tabs.select."))
        cards.firstMatch.swipeLeft()
        XCTAssertTrue(app.staticTexts["1 Tabs"].waitForExistence(timeout: 5))
        capture("dismissed-tab", app)
        app.buttons["Done"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
