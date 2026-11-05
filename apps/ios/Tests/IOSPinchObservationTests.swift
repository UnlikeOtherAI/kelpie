import UIKit
import WebKit
import XCTest
@testable import Kelpie

final class IOSPinchObservationTests: XCTestCase {
    @MainActor
    func testObserverRetiresAndRejectsChangedDocument() {
        #if DEBUG
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 640))
        let view = WKWebView(frame: window.bounds)
        window.addSubview(view)
        XCTAssertEqual(IOSPinchObservation.sample(view: view)["armed"] as? Bool, true)
        let first = IOSPinchObservation.sample(view: view)
        XCTAssertEqual(first["sameView"] as? Bool, true)
        XCTAssertEqual(first["sameDocument"] as? Bool, true)
        XCTAssertEqual(first["began"] as? Int, 0)

        XCTAssertEqual(IOSPinchObservation.sample(view: view)["armed"] as? Bool, true)
        ConnectDocument.navigated(view)
        let changed = IOSPinchObservation.sample(view: view)
        XCTAssertEqual(changed["sameView"] as? Bool, true)
        XCTAssertEqual(changed["sameDocument"] as? Bool, false)
        #endif
    }
}
