import AppKit
import XCTest
@testable import Kelpie

final class ScriptCaptureTests: XCTestCase {
    @MainActor
    func testArtifactChunksRequireAdmittedOwnerAndExactRun() throws {
        let store = ScriptArtifactStore()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data([0, 1, 2, 3, 4]).write(to: file)
        let manifest = try store.add(url: file, runID: "run", mimeType: "image/png", owner: "owner")
        let artifact = try XCTUnwrap(manifest["id"] as? String)
        let body: [String: Any] = ["runId": "run", "artifactId": artifact, "offset": 1, "length": 2]
        let chunk = store.read(body, owner: "owner")
        XCTAssertEqual(chunk["data"] as? String, Data([1, 2]).base64EncodedString())
        XCTAssertEqual(chunk["nextOffset"] as? Int, 3)
        XCTAssertEqual(chunk["eof"] as? Bool, false)
        XCTAssertEqual((store.read(body, owner: "other")["error"] as? [String: Any])?["code"] as? String, "ARTIFACT_NOT_FOUND")
        var wrongRun = body
        wrongRun["runId"] = "other"
        XCTAssertNotNil(store.read(wrongRun, owner: "owner")["error"])
        var oversized = body
        oversized["length"] = 1048577
        XCTAssertNotNil(store.read(oversized, owner: "owner")["error"])
        var pastEnd = body
        pastEnd["offset"] = 6
        XCTAssertNotNil(store.read(pastEnd, owner: "owner")["error"])
    }

    @MainActor
    func testCleanupRetainsRegisteredArtifactThroughDirectoryAliasAndDiscardRemovesIt() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("real", isDirectory: true)
        let alias = base.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let directory = alias.appendingPathComponent("capture", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let file = directory.appendingPathComponent("frame.png")
        let orphan = directory.appendingPathComponent("orphan.png")
        try Data([1, 2, 3]).write(to: file)
        try Data([4]).write(to: orphan)
        let store = ScriptArtifactStore()
        let manifest = try store.add(url: file, runID: "run", mimeType: "image/png", owner: "owner")
        let body: [String: Any] = ["runId": "run", "artifactId": try XCTUnwrap(manifest["id"] as? String)]

        ScriptCaptureOutputCleanup.prune(directory: directory, retaining: [file])
        XCTAssertEqual(store.read(body, owner: "owner")["data"] as? String, Data([1, 2, 3]).base64EncodedString())
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        try FileManager.default.removeItem(at: directory)
        XCTAssertEqual((store.read(body, owner: "owner")["error"] as? [String: Any])?["code"] as? String, "ARTIFACT_READ_FAILED")
    }

    @MainActor
    func testPresentationCurvesShareEndpointsAndHaveDifferentBends() {
        let start = CGPoint(x: 10, y: 20)
        let end = CGPoint(x: 210, y: 120)
        for curve in ["s", "c"] {
            XCTAssertEqual(ScriptPresentation.path(from: start, to: end, progress: 0, curve: curve), start)
            XCTAssertEqual(ScriptPresentation.path(from: start, to: end, progress: 1, curve: curve), end)
            XCTAssertEqual(ScriptPresentation.path(from: start, to: end, progress: -1, curve: curve), start)
        }
        let sMid = ScriptPresentation.path(from: start, to: end, progress: 0.5, curve: "s")
        XCTAssertEqual(sMid.x, 110, accuracy: 0.001)
        XCTAssertEqual(sMid.y, 70, accuracy: 0.001)
        XCTAssertNotEqual(sMid, ScriptPresentation.path(from: start, to: end, progress: 0.5, curve: "c"))
    }
    func testFinalizingRunKeepsRecordingGateUntilCleanupReleasesIt() {
        let state = ScriptPlaybackState()
        XCTAssertTrue(state.start(totalActions: 1, continueOnError: false, holdSession: true))
        state.recordSuccess(index: 0)
        XCTAssertEqual(state.finishSuccess()["success"] as? Bool, true)
        XCTAssertNotNil(state.recordingError(for: "play-script"))
        XCTAssertFalse(state.start(totalActions: 1, continueOnError: false))
        XCTAssertNotNil(state.requestAbort())
        state.releaseHeldSession()
        XCTAssertNil(state.recordingError(for: "play-script"))
        XCTAssertTrue(state.start(totalActions: 1, continueOnError: false))
    }

}
