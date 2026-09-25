import XCTest
import UIKit

final class BrowserChromeUITests: XCTestCase {
    @MainActor
    func testNativeChromeJourney() {
        continueAfterFailure = false
        let tablet = UIDevice.current.userInterfaceIdiom == .pad
        XCUIDevice.shared.orientation = tablet ? .landscapeLeft : .portrait
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
        app.buttons.matching(identifier: "browser.tabs.add").allElementsBoundByIndex.last?.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let start = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -140)))
        let overview = app.otherElements["browser.tabs.overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 Tabs"].exists)
        capture("overview", app)

        let cards = overview.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.tabs.select."))
        cards.firstMatch.swipeLeft()
        XCTAssertTrue(app.staticTexts["1 Tabs"].waitForExistence(timeout: 5))
        capture("dismissed-tab", app)
        cards.firstMatch.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if tablet { verifyTabletOverflow(app) }
    }

    @MainActor
    private func verifyTabletOverflow(_ app: XCUIApplication) {
        for _ in 0..<7 { app.buttons["browser.tabs.add"].tap() }
        let closeButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.tabs.close."))
        XCTAssertEqual(closeButtons.count, 8)
        let activeClose = closeButtons.allElementsBoundByIndex.last
        XCTAssertTrue(activeClose?.isHittable == true)
        capture("tablet-overflow", app)
        activeClose?.tap()
        XCTAssertEqual(closeButtons.count, 7)
        capture("tablet-active-closed", app)
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
