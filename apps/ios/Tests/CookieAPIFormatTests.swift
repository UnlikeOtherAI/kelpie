import XCTest
@testable import KelpieBrowser

final class CookieAPIFormatTests: XCTestCase {
    func testAPIOutputUsesISO8601WithMilliseconds() {
        let wire: [String: Any] = ["name": "sid", "expires": NSNumber(value: Int64(1_777_507_200))]
        XCTAssertEqual(CookieAPIFormat.apiJSON(fromWire: wire)["expires"] as? String, "2026-04-30T00:00:00.000Z")
        XCTAssertTrue(CookieAPIFormat.apiJSON(fromWire: ["expires": NSNull()])["expires"] is NSNull)
        XCTAssertTrue(CookieAPIFormat.expires(nil) is NSNull)
    }

    func testAPIInputAcceptsISOAndUnixSeconds() throws {
        for value: Any in ["2026-04-30T00:00:00.000Z", "2026-04-30T00:00:00Z", NSNumber(value: Int64(1_777_507_200))] {
            let wire = try XCTUnwrap(CookieAPIFormat.wireJSON(fromAPI: ["expires": value]))
            XCTAssertEqual(SyncJSON.int64(wire["expires"]), 1_777_507_200)
        }
        XCTAssertTrue(try XCTUnwrap(CookieAPIFormat.wireJSON(fromAPI: [:]))["expires"] is NSNull)
    }

    func testAPIInputRejectsUnparseableExpiry() {
        XCTAssertNil(CookieAPIFormat.wireJSON(fromAPI: ["expires": "next tuesday"]))
        XCTAssertNil(CookieAPIFormat.wireJSON(fromAPI: ["expires": 1.5]))
    }
}
