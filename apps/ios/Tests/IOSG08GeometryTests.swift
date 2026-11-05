import UIKit
import XCTest
@testable import Kelpie

#if DEBUG
final class IOSG08GeometryTests: XCTestCase {
    @MainActor
    func testConstantG08GeometryBindsEverySampleToBothDocuments() throws {
        func viewport(id: String?, x: CGFloat = 0) -> IOSWorkflowTab.Viewport {
            IOSWorkflowTab.Viewport(
                bounds: CGSize(width: 402, height: 874), layout: CGSize(width: 402, height: 778),
                visible: CGRect(x: x, y: 0, width: 402, height: 778), scale: 1, pixelRatio: 3,
                content: CGRect(x: 0, y: 62, width: 402, height: 778), fixtureDocumentID: id
            )
        }
        XCTAssertEqual(IOSWorkflowTab.fixtureID("1234567890123-abc123"), "1234567890123-abc123")
        for invalid in ["secret", "1234567890123-", "1234567890123-ABC", "1234567890123-abcdefghijklmnopq",
                        "1234567890123-abc\n", "123456789012-abc"] {
            XCTAssertNil(IOSWorkflowTab.fixtureID(invalid))
        }
        let scene = viewport(id: "1234567890123-abc")
        var valid = IOSG08GeometryEvidence()
        valid.record(document: "native-1", viewport: scene)
        valid.record(document: "native-1", viewport: scene)
        let geometry = try XCTUnwrap(valid.manifest(encodedFrames: 2))
        XCTAssertEqual(geometry["nativeDocumentId"] as? String, "native-1")
        XCTAssertEqual(geometry["fixtureDocumentId"] as? String, "1234567890123-abc")
        XCTAssertEqual(geometry["observedFrames"] as? Int, 2)
        XCTAssertEqual(geometry["encodedFrames"] as? Int, 2)
        XCTAssertEqual((geometry["contentRect"] as? [String: CGFloat])?["y"], 62)
        XCTAssertNil(valid.manifest(encodedFrames: 3))
        XCTAssertNil(valid.manifest(encodedFrames: 0))

        var scrolled = valid
        scrolled.record(document: "native-1", viewport: viewport(id: "1234567890123-abc", x: 1))
        XCTAssertNil(scrolled.manifest(encodedFrames: 2))
        var newDocument = valid
        newDocument.record(document: "native-2", viewport: scene)
        XCTAssertNil(newDocument.manifest(encodedFrames: 2))
        var changedFixture = valid
        changedFixture.record(document: "native-1", viewport: viewport(id: "1234567890123-def"))
        XCTAssertNil(changedFixture.manifest(encodedFrames: 2))
        var absent = IOSG08GeometryEvidence()
        absent.record(document: "native-1", viewport: viewport(id: nil))
        XCTAssertNil(absent.manifest(encodedFrames: 1))
        absent.record(document: "native-1", viewport: scene)
        XCTAssertNil(absent.manifest(encodedFrames: 1))
    }
}
#endif
