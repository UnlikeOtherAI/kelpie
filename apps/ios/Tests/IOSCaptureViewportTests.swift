import UIKit
import XCTest
@testable import Kelpie

final class IOSCaptureViewportTests: XCTestCase {
    @MainActor
    func testFirstCaptureRequiresInsetPropagationIncludingZoom() {
        func viewport(width: CGFloat, height: CGFloat, native: CGSize, scale: CGFloat = 1) -> IOSWorkflowTab.Viewport {
            IOSWorkflowTab.Viewport(bounds: native, layout: CGSize(width: width, height: height),
                                    visible: CGRect(x: 0, y: 0, width: width, height: height),
                                    scale: scale, pixelRatio: 3)
        }
        let phone = CGSize(width: 402, height: 874)
        let old = viewport(width: 402, height: 812, native: phone)
        let settled = viewport(width: 402, height: 778, native: phone)
        XCTAssertFalse(IOSCaptureViewportStability.matchesInsets(old, top: 62, bottom: 34))
        XCTAssertTrue(IOSCaptureViewportStability.matchesInsets(settled, top: 62, bottom: 34))
        let zoomed = viewport(width: 201, height: 389, native: phone, scale: 2)
        XCTAssertTrue(IOSCaptureViewportStability.matchesInsets(zoomed, top: 62, bottom: 34))
        let pad = CGSize(width: 1024, height: 1366)
        XCTAssertFalse(IOSCaptureViewportStability.matchesInsets(viewport(width: 1024, height: 1366, native: pad),
                                                                 top: 0, bottom: 20))
        XCTAssertTrue(IOSCaptureViewportStability.matchesInsets(viewport(width: 1024, height: 1346, native: pad),
                                                                top: 0, bottom: 20))
        XCTAssertFalse(IOSCaptureViewportStability.matchesInsets(settled, top: -1, bottom: 34))
        let landscape = viewport(width: 389, height: 190.5, native: CGSize(width: 874, height: 402), scale: 2)
        XCTAssertTrue(IOSCaptureViewportStability.matchesInsets(landscape, top: 0, bottom: 21, left: 62, right: 34))
        XCTAssertFalse(IOSCaptureViewportStability.matchesInsets(landscape, top: 0, bottom: 21, left: 0, right: 0))
        XCTAssertFalse(IOSCaptureViewportStability.matchesInsets(landscape, top: 0, bottom: 21, left: 874, right: 0))
        var stability = IOSCaptureViewportStability()
        XCTAssertFalse(stability.observe(settled, at: 0))
        XCTAssertFalse(stability.observe(settled, at: 0.3, admissible: false))
        XCTAssertFalse(stability.observe(settled, at: 0.31))
        XCTAssertFalse(stability.observe(settled, at: 0.5))
        XCTAssertTrue(stability.observe(settled, at: 0.52))
    }

    @MainActor
    func testProjectionUsesInsetContentOriginAndVisualViewport() {
        let phone = IOSWorkflowTab.Viewport(
            bounds: CGSize(width: 402, height: 874), layout: CGSize(width: 402, height: 778),
            visible: CGRect(x: 0, y: 0, width: 402, height: 778), scale: 1, pixelRatio: 3,
            content: CGRect(x: 0, y: 62, width: 402, height: 778)
        )
        XCTAssertEqual(phone.displayPoint(CGPoint(x: 175, y: 340)), CGPoint(x: 175, y: 402))
        let pad = IOSWorkflowTab.Viewport(
            bounds: CGSize(width: 1024, height: 1366), layout: CGSize(width: 1024, height: 1346),
            visible: CGRect(x: 0, y: 0, width: 1024, height: 1346), scale: 1, pixelRatio: 2,
            content: CGRect(x: 0, y: 0, width: 1024, height: 1346)
        )
        XCTAssertEqual(pad.displayPoint(CGPoint(x: 175, y: 340)), CGPoint(x: 175, y: 340))
        let zoom = IOSWorkflowTab.Viewport(
            bounds: CGSize(width: 874, height: 402), layout: CGSize(width: 389, height: 190.5),
            visible: CGRect(x: 10, y: 20, width: 389, height: 190.5), scale: 2, pixelRatio: 3,
            content: CGRect(x: 62, y: 0, width: 778, height: 381)
        )
        XCTAssertEqual(zoom.displayPoint(CGPoint(x: 30, y: 40)), CGPoint(x: 102, y: 40))
        XCTAssertEqual(zoom.pointsPerCSSX, 2)
    }

    @MainActor
    func testUnsettledInsetAdmissionHonorsDeadlineAndStop() async throws {
        let viewport = IOSWorkflowTab.Viewport(bounds: CGSize(width: 402, height: 874),
                                               layout: CGSize(width: 402, height: 812),
                                               visible: CGRect(x: 0, y: 0, width: 402, height: 812),
                                               scale: 1, pixelRatio: 3)
        var time = 0.0
        do {
            _ = try await IOSCaptureViewportStability.wait(
                deadline: 0.1, check: {}, read: { viewport }, admissible: { _ in false },
                now: { time }, pause: { time += 0.02 }
            )
            XCTFail("Inconsistent insets must reach the original deadline")
        } catch { XCTAssertEqual((error as? IOSWorkflowFailure)?.code, "CAPTURE_VIEWPORT_UNSTABLE") }

        var checks = 0
        do {
            _ = try await IOSCaptureViewportStability.wait(
                deadline: 1, check: {
                    checks += 1
                    if checks > 2 { throw IOSWorkflowFailure("SCRIPT_ABORTED") }
                }, read: { viewport }, admissible: { _ in false }, now: { time }, pause: { time += 0.02 }
            )
            XCTFail("Stop must interrupt the inset admission")
        } catch { XCTAssertEqual((error as? IOSWorkflowFailure)?.code, "SCRIPT_ABORTED") }
    }
}
