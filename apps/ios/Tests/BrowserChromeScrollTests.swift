import XCTest
@testable import Kelpie

final class BrowserChromeScrollTests: XCTestCase {
    func testFingerDirectionChangesChrome() {
        var state = BrowserChromeScroll()
        XCTAssertEqual(state.update(translation: 25, offset: 100, maximum: 1000, userDragging: true), .down)
        XCTAssertEqual(state.update(translation: 0, offset: 75, maximum: 1000, userDragging: true), .up)
    }

    func testInsetOrDecelerationOffsetsCannotReverseChrome() {
        var state = BrowserChromeScroll()
        XCTAssertEqual(state.update(translation: 25, offset: 100, maximum: 1000, userDragging: true), .down)
        XCTAssertNil(state.update(translation: 25, offset: 72, maximum: 1000, userDragging: true))
        XCTAssertNil(state.update(translation: 25, offset: 500, maximum: 1000, userDragging: false))
        XCTAssertNil(state.update(translation: 25, offset: 472, maximum: 1000, userDragging: false))
    }

    func testRubberBandMotionDoesNotChangeChrome() {
        var state = BrowserChromeScroll()
        XCTAssertNil(state.update(translation: -40, offset: -40, maximum: 1000, userDragging: true))
        XCTAssertNil(state.update(translation: -30, offset: 0, maximum: 1000, userDragging: true))
        XCTAssertEqual(state.update(translation: 0, offset: 30, maximum: 1000, userDragging: true), .down)
        XCTAssertNil(state.update(translation: 80, offset: 1020, maximum: 1000, userDragging: true))
    }

    func testSmallMotionAndUnscrollablePagesDoNotCollapse() {
        var state = BrowserChromeScroll()
        XCTAssertNil(state.update(translation: 30, offset: 0, maximum: 0, userDragging: true))
        state = BrowserChromeScroll()
        XCTAssertNil(state.update(translation: 10, offset: 100, maximum: 1000, userDragging: true))
        XCTAssertEqual(state.update(translation: 20, offset: 110, maximum: 1000, userDragging: true), .down)
    }
}
