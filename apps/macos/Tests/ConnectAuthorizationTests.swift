import XCTest
import WebKit
@testable import Kelpie

final class ConnectAuthorizationTests: XCTestCase {
    #if os(iOS)
    @MainActor
    func testPageContextReadKeepsItsBeforeAndAfterJobFence() async throws {
        let context = HandlerContext()
        let view = WKWebView()
        context.webView = view
        context.remoteDocumentGuard = { false }
        do {
            _ = try await PageTextSnapshot.object(context: context, body: [:], script: "({value:1})")
            XCTFail("Revoked job must not read page context")
        } catch is CancellationError { }
        var checks = 0
        context.remoteDocumentGuard = { checks += 1; return checks == 1 }
        do {
            _ = try await PageTextSnapshot.object(context: context, body: [:], script: "({value:1})")
            XCTFail("Revocation during evaluation must discard page context")
        } catch is CancellationError { }
        XCTAssertEqual(checks, 2)
    }
    #endif
    @MainActor
    func testNavigationCompletionBelongsToItsIssuedNativeObject() {
        let token = NSObject()
        let lease = ConnectNavigationLease(initial: "old")
        lease.issued(token)
        XCTAssertFalse(lease.allowsRead(version: "old", loading: false, authorized: true))
        lease.started(previous: "old", version: "new", navigation: token)
        XCTAssertTrue(lease.allowsRead(version: "new", loading: false, authorized: true))
        XCTAssertFalse(lease.allowsRead(version: "new", loading: true, authorized: true))
        XCTAssertFalse(lease.allowsRead(version: "new", loading: false, authorized: false))
        lease.started(previous: "new", version: "later", navigation: NSObject())
        XCTAssertFalse(lease.allowsRead(version: "later", loading: false, authorized: true))
    }

    @MainActor
    func testUnrelatedNavigationCannotSupplyCompletionMetadata() {
        let lease = ConnectNavigationLease(initial: "old")
        lease.issued(NSObject())
        lease.started(previous: "old", version: "unrelated", navigation: NSObject())
        XCTAssertFalse(lease.allowsRead(version: "unrelated", loading: false, authorized: true))
        XCTAssertFalse(lease.allowsWait(version: "unrelated", authorized: true))
    }

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
