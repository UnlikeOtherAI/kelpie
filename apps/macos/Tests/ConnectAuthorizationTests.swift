import XCTest
@testable import Kelpie

final class ConnectAuthorizationTests: XCTestCase {
    func testWireTextBoundsPreserveUnicode() {
        XCTAssertEqual(ConnectText.bounded(String(repeating: "😀", count: 100), to: 120).utf16.count, 120)
        XCTAssertEqual(ConnectText.bounded("a😀", to: 2), "a")
        XCTAssertEqual(ConnectText.bounded("e\u{301}", to: 1), "")
    }

    func testCancelledAndReplacementJobsCannotBorrowAuthority() throws {
        let command: [String: Any] = ["jobId": "job", "attemptId": "first", "deadline": "2030-01-01T00:00:00.123Z"]
        let authorization = try XCTUnwrap(ConnectAuthorization(command))
        let now = try XCTUnwrap(ConnectAuthorization.parseDeadline("2029-01-01T00:00:00Z"))
        XCTAssertTrue(authorization.matches(command, now: now))
        XCTAssertFalse(authorization.matches(nil, now: now))
        XCTAssertFalse(authorization.matches(["jobId": "job", "attemptId": "replacement"], now: now))
        XCTAssertFalse(authorization.matches(["jobId": "other", "attemptId": "first"], now: now))
        XCTAssertFalse(authorization.matches(command, now: authorization.deadline))
        XCTAssertNil(ConnectAuthorization(["jobId": "job", "attemptId": "first", "deadline": "invalid"]))
    }

    @MainActor
    func testNavigationChangesOnlyThatDocumentsPin() {
        let first = NSObject()
        let second = NSObject()
        let firstPin = ConnectDocument.version(first)
        let secondPin = ConnectDocument.version(second)
        XCTAssertEqual(ConnectDocument.version(first), firstPin)
        ConnectDocument.navigated(first)
        XCTAssertNotEqual(ConnectDocument.version(first), firstPin)
        XCTAssertEqual(ConnectDocument.version(second), secondPin)
    }
}
