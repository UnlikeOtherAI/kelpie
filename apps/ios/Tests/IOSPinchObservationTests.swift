import UIKit
import WebKit
import XCTest
@testable import Kelpie

final class IOSPinchObservationTests: XCTestCase {
    @MainActor
    func testObserverRetiresAndRejectsChangedDocument() async throws {
        #if DEBUG
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 640))
        controller.view.addSubview(view)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        view.loadHTMLString("<meta name=viewport content='width=device-width,initial-scale=1'><p>Observer</p>", baseURL: nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while (view.isLoading || view.scrollView.pinchGestureRecognizer == nil), ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let availability = XCTAttachment(string: "window=\(view.window != nil) recognizer=\(view.scrollView.pinchGestureRecognizer != nil)")
        availability.name = "Standalone WebKit observer readiness"
        availability.lifetime = .keepAlways
        add(availability)
        XCTAssertNotNil(view.window)
        XCTAssertNotNil(view.scrollView.pinchGestureRecognizer)
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
