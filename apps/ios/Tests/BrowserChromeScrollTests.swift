import XCTest
@testable import Kelpie

final class BrowserChromeScrollTests: XCTestCase {
    func testOnlyUserScrollingChangesChrome() {
        var state = BrowserChromeScroll()
        XCTAssertNil(state.update(offset: 0, maximum: 1000, height: 600, userScrolling: false))
        XCTAssertNil(state.update(offset: 300, maximum: 1000, height: 600, userScrolling: false))
        XCTAssertEqual(state.update(offset: 325, maximum: 1000, height: 600, userScrolling: true), .down)
        XCTAssertEqual(state.update(offset: 300, maximum: 1000, height: 600, userScrolling: true), .up)
    }

    func testRubberBandAndResizeResetBaseline() {
        var state = BrowserChromeScroll()
        XCTAssertNil(state.update(offset: 980, maximum: 1000, height: 600, userScrolling: false))
        XCTAssertNil(state.update(offset: 1020, maximum: 1000, height: 600, userScrolling: true))
        XCTAssertNil(state.update(offset: 990, maximum: 900, height: 700, userScrolling: true))
        XCTAssertNil(state.update(offset: 800, maximum: 900, height: 600, userScrolling: true))
        XCTAssertEqual(state.update(offset: 770, maximum: 900, height: 600, userScrolling: true), .up)
    }

    func testSmallMotionAndUnscrollablePagesDoNotCollapse() {
        var state = BrowserChromeScroll()
        XCTAssertNil(state.update(offset: 0, maximum: 0, height: 600, userScrolling: false))
        XCTAssertNil(state.update(offset: 30, maximum: 0, height: 600, userScrolling: true))
        XCTAssertNil(state.update(offset: 100, maximum: 1000, height: 600, userScrolling: false))
        XCTAssertNil(state.update(offset: 110, maximum: 1000, height: 600, userScrolling: true))
        XCTAssertEqual(state.update(offset: 120, maximum: 1000, height: 600, userScrolling: true), .down)
    }
}
