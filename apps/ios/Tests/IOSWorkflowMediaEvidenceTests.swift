import XCTest
@testable import Kelpie

final class IOSWorkflowMediaEvidenceTests: XCTestCase {
    @MainActor
    func testDiagnosticRunRotationPreservesCurrentAndRejectsStaleArtifacts() throws {
        #if DEBUG
        for flag in ["--test-paired-geometry-receipt", "--test-g08-document-binding", "--test-pinch-projection"] {
            var current = IOSWorkflowMedia.newTestEvidence(runID: "first", arguments: [flag])
            current["viewportRefusal"] = ["site": "snapshot"]
            let first = try XCTUnwrap(IOSWorkflowMedia.mergeTestArtifact(current, runID: "first", id: "a", facts: [:]))
            XCTAssertNotNil(first["viewportRefusal"])
            let second = IOSWorkflowMedia.newTestEvidence(runID: "second", arguments: [flag])
            XCTAssertNil(IOSWorkflowMedia.mergeTestArtifact(second, runID: "first", id: "stale", facts: [:]))
            let updated = try XCTUnwrap(IOSWorkflowMedia.mergeTestArtifact(second, runID: "second", id: "b", facts: [:]))
            XCTAssertEqual(updated["runId"] as? String, "second")
            XCTAssertNotNil((updated["artifacts"] as? [String: [String: Any]])?["b"])
            XCTAssertNil(updated["viewportRefusal"])
        }
        XCTAssertTrue(IOSWorkflowMedia.newTestEvidence(runID: "none", arguments: []).isEmpty)
        #endif
    }
}
