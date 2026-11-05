import XCTest
@testable import Kelpie

final class IOSWorkflowPresentationModeTests: XCTestCase {
    func testOnlyMovieFormatsSelectImmersiveLayout() throws {
        func bind(_ formats: [String]?, explicit: Bool = false) throws -> IOSBoundWorkflow {
            var actions: [[String: Any]] = [["action": "wait", "ms": 1]]
            if explicit { actions.append(["action": "screenshot", "name": "still"]) }
            var script: [String: Any] = ["version": 1, "tabId": "test-tab", "actions": actions]
            if let formats { script["capture"] = ["formats": formats] }
            return try IOSBoundWorkflow(script)
        }
        XCTAssertFalse(try bind(nil).requiresMovieImmersion)
        XCTAssertFalse(try bind(nil, explicit: true).requiresMovieImmersion)
        XCTAssertFalse(try bind(["screenshots"]).requiresMovieImmersion)
        XCTAssertTrue(try bind(["gif"]).requiresMovieImmersion)
        XCTAssertTrue(try bind(["video"]).requiresMovieImmersion)
        XCTAssertTrue(try bind(["screenshots", "gif", "video"]).requiresMovieImmersion)
    }
}
