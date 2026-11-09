import XCTest
@testable import KelpieBrowser

/// Inputs an unauthenticated LAN peer controls must never crash the app or reach logs.
final class SyncHardeningTests: XCTestCase {
    func testSkewGateSurvivesExtremeClocks() {
        XCTAssertTrue(SyncLimits.withinSkew(1_000_000, 1_000_000 + SyncLimits.maxClockSkewMillis))
        XCTAssertFalse(SyncLimits.withinSkew(1_000_000, 1_000_000 + SyncLimits.maxClockSkewMillis + 1))
        XCTAssertFalse(SyncLimits.withinSkew(Int64.min, 1_767_225_600_000))
        XCTAssertFalse(SyncLimits.withinSkew(Int64.max, -1_767_225_600_000))
        XCTAssertFalse(SyncLimits.withinSkew(Int64.min, Int64.max))
    }

    func testResponseLengthMustBeOneBoundedDecimal() {
        func parse(_ head: String) -> SyncHTTPResponse? {
            SyncHTTPResponse.parse(Data("HTTP/1.1 200 OK\r\n\(head)\r\n\r\n{}".utf8), complete: true)
        }
        XCTAssertEqual(parse("Content-Length: 2")?.status, 200)
        for hostile in ["Content-Length: -1", "Content-Length: +2", "Content-Length: 2x", "Content-Length: ",
                        "Content-Length: 99999999999", "Content-Length: 2\r\nContent-Length: 2"] {
            XCTAssertEqual(parse(hostile)?.status, 0, hostile)
        }
    }

    func testPeerErrorsAreLimitedToDocumentedCodes() {
        XCTAssertEqual(SyncFailure.peer("CLOCK_SKEW", status: 409).code, "CLOCK_SKEW")
        XCTAssertEqual(SyncFailure.peer("eyJhbGciOiJSUzI1NiJ9.reflected.ticket", status: 403).code, "PEER_ERROR")
        XCTAssertEqual(SyncFailure.peer("sid=secret-cookie-value", status: 400).code, "PEER_ERROR")
        XCTAssertEqual(SyncFailure.peer(nil, status: 502).code, "HTTP_502")
        XCTAssertEqual(SyncFailure.peer(42, status: 400).code, "HTTP_400")
    }
}
