import XCTest
@testable import KelpieBrowser

final class Snapshot3DBridgeTests: XCTestCase {
    func testBundledScriptsAssembleInPhaseOrder() throws {
        let script = try Snapshot3DBridge.enterScript
        let setup = try XCTUnwrap(script.range(of: "var LAYER_SPACING"))
        let collect = try XCTUnwrap(script.range(of: "var OVERRIDE_PROPS"))
        let apply = try XCTUnwrap(script.range(of: "htmlEl.style.perspective ="))
        let input = try XCTUnwrap(script.range(of: "function applyTransform()"))
        XCTAssertLessThan(setup.lowerBound, collect.lowerBound)
        XCTAssertLessThan(collect.lowerBound, apply.lowerBound)
        XCTAssertLessThan(apply.lowerBound, input.lowerBound)
        XCTAssertTrue(try Snapshot3DBridge.exitScript.contains("delete window.__m3d"))
    }

    func testMissingResourceThrowsInsteadOfCrashing() {
        XCTAssertThrowsError(try Snapshot3DBridge.loadResource(named: "missing-inspector-resource")) { error in
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            XCTAssertEqual((error as NSError).code, CocoaError.fileNoSuchFile.rawValue)
        }
    }
}
