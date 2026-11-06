import UIKit
import WebKit
import XCTest
@testable import Kelpie

final class IOSViewportInsetReconciliationTests: XCTestCase {
    @MainActor
    func testChangedViewportRangeWithUnchangedScrollClearance() {
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 640))
        view.scrollView.contentInset.bottom = 0
        TabWebViewContainer.reconcileInsets(view, clearance: 0, viewport: 0...24)
        XCTAssertEqual(view.scrollView.contentInset.bottom, 0)
        XCTAssertEqual(view.minimumViewportInset.bottom, 0)
        XCTAssertEqual(view.maximumViewportInset.bottom, 24)

        TabWebViewContainer.reconcileInsets(view, clearance: 0, viewport: 0...48)
        XCTAssertEqual(view.scrollView.contentInset.bottom, 0)
        XCTAssertEqual(view.minimumViewportInset.bottom, 0)
        XCTAssertEqual(view.maximumViewportInset.bottom, 48)

        TabWebViewContainer.reconcileInsets(view, clearance: 0, viewport: 0...0)
        XCTAssertEqual(view.scrollView.contentInset.bottom, 0)
        XCTAssertEqual(view.minimumViewportInset.bottom, 0)
        XCTAssertEqual(view.maximumViewportInset.bottom, 0)
    }
}
