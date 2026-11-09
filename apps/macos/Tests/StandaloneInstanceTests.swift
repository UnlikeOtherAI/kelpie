import XCTest

final class StandaloneInstanceTests: XCTestCase {
    func testOwnershipSurvivesRejectedLaunchAndReleasesOnExit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lock = directory.appendingPathComponent("standalone.lock")
        var first: StandaloneInstance? = try StandaloneInstance(lockURL: lock)
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try StandaloneInstance(lockURL: lock)) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .EAGAIN)
        }
        XCTAssertThrowsError(try StandaloneInstance(lockURL: lock))
        first = nil
        let recovered = try StandaloneInstance(lockURL: lock)
        withExtendedLifetime(recovered) { XCTAssertTrue(FileManager.default.fileExists(atPath: lock.path)) }
    }

    func testDoesNotFollowSymlink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target")
        try Data("untouched".utf8).write(to: target)
        let lock = directory.appendingPathComponent("standalone.lock")
        try FileManager.default.createSymbolicLink(at: lock, withDestinationURL: target)
        XCTAssertThrowsError(try StandaloneInstance(lockURL: lock))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "untouched")
    }
}
