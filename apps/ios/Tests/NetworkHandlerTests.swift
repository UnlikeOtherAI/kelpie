import XCTest
@testable import KelpieBrowser

/// Deterministic unit tests for `NetworkHandler`'s pure status/`since` parsing.
/// These call the static helpers directly — no `HandlerContext`, network, or IO.
final class NetworkHandlerTests: XCTestCase {
    // MARK: - parseStatusCategory

    func testParseStatusCategoryAcceptsKnownValues() {
        XCTAssertEqual(NetworkHandler.parseStatusCategory("success"), "success")
        XCTAssertEqual(NetworkHandler.parseStatusCategory("error"), "error")
        XCTAssertEqual(NetworkHandler.parseStatusCategory("pending"), "pending")
    }

    func testParseStatusCategoryNormalizesCaseAndWhitespace() {
        XCTAssertEqual(NetworkHandler.parseStatusCategory("  Success  "), "success")
    }

    func testParseStatusCategoryRejectsUnknownAndNonString() {
        XCTAssertNil(NetworkHandler.parseStatusCategory("redirect"))
        XCTAssertNil(NetworkHandler.parseStatusCategory(nil))
        XCTAssertNil(NetworkHandler.parseStatusCategory(200))
    }

    // MARK: - matchesStatusCategory

    func testSuccessCategoryCovers2xxAnd3xx() {
        XCTAssertTrue(NetworkHandler.matchesStatusCategory(200, "success"))
        XCTAssertTrue(NetworkHandler.matchesStatusCategory(204, "success"))
        XCTAssertTrue(NetworkHandler.matchesStatusCategory(301, "success"))
        XCTAssertTrue(NetworkHandler.matchesStatusCategory(399, "success"))
    }

    func testSuccessCategoryExcludesErrorsAndPending() {
        XCTAssertFalse(NetworkHandler.matchesStatusCategory(404, "success"))
        XCTAssertFalse(NetworkHandler.matchesStatusCategory(nil, "success"))
        XCTAssertFalse(NetworkHandler.matchesStatusCategory(0, "success"))
    }

    func testErrorCategoryCovers4xxAndAbove() {
        XCTAssertTrue(NetworkHandler.matchesStatusCategory(400, "error"))
        XCTAssertTrue(NetworkHandler.matchesStatusCategory(500, "error"))
        XCTAssertFalse(NetworkHandler.matchesStatusCategory(399, "error"))
        XCTAssertFalse(NetworkHandler.matchesStatusCategory(nil, "error"))
    }

    func testPendingCategoryMatchesMissingOrZero() {
        XCTAssertTrue(NetworkHandler.matchesStatusCategory(nil, "pending"))
        XCTAssertTrue(NetworkHandler.matchesStatusCategory(0, "pending"))
        XCTAssertFalse(NetworkHandler.matchesStatusCategory(200, "pending"))
    }

    func testUnknownCategoryNeverMatches() {
        XCTAssertFalse(NetworkHandler.matchesStatusCategory(200, "bogus"))
    }

    func testErrorFilterIncludesTransportFailureAndKeepsSummary() {
        let result = NetworkHandler.networkLog([
            ["type": "fetch", "status": 204],
            ["type": "fetch", "status": 404, "method": "POST"],
            ["type": "xhr", "status": NSNull(), "failure": "timed out"],
            ["type": "image", "status": NSNull()]
        ], filters: ["status": "error", "limit": 1])
        let entries = result["entries"] as? [[String: Any]]
        let summary = result["summary"] as? [String: Any]
        XCTAssertEqual(entries?.first?["method"] as? String, "POST")
        XCTAssertEqual(result["count"] as? Int, 1)
        XCTAssertEqual(result["hasMore"] as? Bool, true)
        XCTAssertEqual(summary?["totalRequests"] as? Int, 4)
        XCTAssertEqual(summary?["errors"] as? Int, 2)
    }

    // MARK: - parseSinceMillis

    func testParseSinceFromNumber() {
        XCTAssertEqual(NetworkHandler.parseSinceMillis(1_700_000_000_000), 1_700_000_000_000)
        XCTAssertEqual(NetworkHandler.parseSinceMillis(Double(1_700_000_000_000)), 1_700_000_000_000)
    }

    func testParseSinceFromNumericString() {
        XCTAssertEqual(NetworkHandler.parseSinceMillis(" 1700000000000 "), 1_700_000_000_000)
    }

    func testParseSinceFromISO8601() {
        // 2021-01-01T00:00:00Z == 1609459200000 ms since epoch.
        XCTAssertEqual(NetworkHandler.parseSinceMillis("2021-01-01T00:00:00Z"), 1_609_459_200_000)
    }

    func testParseSinceFromISO8601WithFractionalSeconds() {
        XCTAssertEqual(NetworkHandler.parseSinceMillis("2021-01-01T00:00:00.500Z"), 1_609_459_200_500)
    }

    func testParseSinceReturnsNilForGarbageAndNil() {
        XCTAssertNil(NetworkHandler.parseSinceMillis(nil))
        XCTAssertNil(NetworkHandler.parseSinceMillis("not-a-date"))
    }

    // MARK: - parseISO8601Millis

    func testParseISO8601MillisHandlesBothFormats() {
        XCTAssertEqual(NetworkHandler.parseISO8601Millis("2021-01-01T00:00:00Z"), 1_609_459_200_000)
        XCTAssertEqual(NetworkHandler.parseISO8601Millis("2021-01-01T00:00:00.000Z"), 1_609_459_200_000)
        XCTAssertNil(NetworkHandler.parseISO8601Millis("garbage"))
    }
}
