import XCTest
@testable import Kelpie

final class BrowserChromeScrollTests: XCTestCase {
    func testDownHidesAndFirstUpwardTickReveals() {
        XCTAssertEqual(BrowserChromeScroll.collapsed(deltaX: 0, deltaY: -12), true)
        XCTAssertEqual(BrowserChromeScroll.collapsed(deltaX: 0, deltaY: 0.02), false)
    }

    func testHorizontalAndStationaryEventsDoNotChangeChrome() {
        XCTAssertNil(BrowserChromeScroll.collapsed(deltaX: 12, deltaY: -2))
        XCTAssertNil(BrowserChromeScroll.collapsed(deltaX: -12, deltaY: 2))
        XCTAssertNil(BrowserChromeScroll.collapsed(deltaX: 0, deltaY: 0))
        XCTAssertNil(BrowserChromeScroll.collapsed(deltaX: 2, deltaY: 2))
    }
}
