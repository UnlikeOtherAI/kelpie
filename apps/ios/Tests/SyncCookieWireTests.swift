import WebKit
import XCTest
@testable import KelpieBrowser

final class SyncCookieWireTests: XCTestCase {
    private let url = URL(string: "https://www.example.com/")!
    private let tomorrow = Int64(Date().timeIntervalSince1970) + 86_400

    private func header(_ value: String) throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": value], for: url).first)
    }

    private func roundTrip(_ json: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        let cookie = try XCTUnwrap(SyncCookieWire.httpCookie(from: json), file: file, line: line)
        return try XCTUnwrap(SyncCookieWire.json(from: cookie), file: file, line: line)
    }

    private func assertSame(_ lhs: [String: Any], _ rhs: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs as NSDictionary, rhs as NSDictionary, file: file, line: line)
    }

    func testHttpOnlySecureCookieRoundTrips() throws {
        let cookie = try header("sid=abc; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=86400")
        let json = try XCTUnwrap(SyncCookieWire.json(from: cookie))
        XCTAssertEqual(json["httpOnly"] as? Bool, true)
        XCTAssertEqual(json["secure"] as? Bool, true)
        XCTAssertEqual(json["sameSite"] as? String, "Lax")
        XCTAssertEqual(json["domain"] as? String, "www.example.com")
        XCTAssertNotNil(SyncJSON.int64(json["expires"]))
        assertSame(try roundTrip(json), json)
    }

    func testSessionCookieHasNullExpiryAndStaysSessionOnly() throws {
        let json: [String: Any] = [
            "domain": ".example.com", "path": "/", "name": "s", "value": "v", "expires": NSNull(),
            "secure": false, "httpOnly": true, "sameSite": "Unspecified"
        ]
        let cookie = try XCTUnwrap(SyncCookieWire.httpCookie(from: json))
        XCTAssertTrue(cookie.isSessionOnly)
        XCTAssertTrue(cookie.isHTTPOnly)
        assertSame(try roundTrip(json), json)
    }

    func testEverySameSiteValueRoundTrips() throws {
        for value in ["Strict", "Lax", "None", "Unspecified"] {
            let json: [String: Any] = [
                "domain": "example.com", "path": "/a", "name": "n", "value": "v;,= x", "expires": NSNumber(value: tomorrow),
                "secure": true, "httpOnly": false, "sameSite": value
            ]
            assertSame(try roundTrip(json), json)
        }
        XCTAssertEqual(try SyncCookieWire.json(from: header("a=b; SameSite=None; Secure"))?["sameSite"] as? String, "None")
        XCTAssertEqual(try SyncCookieWire.json(from: header("a=b; samesite=strict"))?["sameSite"] as? String, "Strict")
        XCTAssertEqual(try SyncCookieWire.json(from: header("a=b"))?["sameSite"] as? String, "Unspecified")
    }

    func testHostOnlyAndDomainCookiesKeepTheirShape() throws {
        XCTAssertEqual(try SyncCookieWire.json(from: header("a=b"))?["domain"] as? String, "www.example.com")
        XCTAssertEqual(try SyncCookieWire.json(from: header("a=b; Domain=example.com"))?["domain"] as? String, ".example.com")
    }

    func testInvalidWireCookiesAreRefused() {
        let valid: [String: Any] = ["domain": "example.com", "path": "/", "name": "n", "value": "v", "sameSite": "Lax"]
        XCTAssertNotNil(SyncCookieWire.httpCookie(from: valid))
        for (field, value) in [("sameSite", "Bogus"), ("expires", 1.5), ("secure", "yes"), ("domain", ""), ("name", ""), ("path", "x")] as [(String, Any)] {
            var invalid = valid
            invalid[field] = value
            XCTAssertNil(SyncCookieWire.httpCookie(from: invalid), "\(field) = \(value)")
        }
        XCTAssertNil(SyncCookieWire.httpCookie(from: ["domain": "example.com", "path": "/", "name": "n", "sameSite": "Lax"]))
    }

    /// The real WebKit store: write, read back, enumerate and delete an HttpOnly cookie.
    @MainActor
    func testWebKitSourceAppliesAndReadsBackHttpOnlyCookies() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        defer { withExtendedLifetime(dataStore) {} }
        let source = WebKitSyncCookieSource(store: dataStore.httpCookieStore)
        var changes = 0
        source.setChangeHandler { changes += 1 }
        let cookie: [String: Any] = [
            "domain": ".example.com", "path": "/", "name": "sid", "value": "secret", "expires": NSNumber(value: tomorrow),
            "secure": true, "httpOnly": true, "sameSite": "Strict"
        ]
        let set = await source.apply(SyncCookieOp(id: 0, isDelete: false, cookieJSON: SyncJSON.string(cookie)))
        XCTAssertTrue(set.ok)
        let readback = try XCTUnwrap(SyncJSON.value(set.readbackJSON) as? [[String: Any]])
        XCTAssertEqual(readback.count, 1)
        assertSame(try XCTUnwrap(readback.first), cookie)

        let snapshot = try await source.snapshot()
        XCTAssertEqual(snapshot.coverageJSON, #"{"all":true}"#)
        XCTAssertEqual((SyncJSON.value(snapshot.cookiesJSON) as? [Any])?.count, 1)

        let none = await source.apply(SyncCookieOp(id: 1, isDelete: false, cookieJSON: SyncJSON.string(
            cookie.merging(["name": "cross", "sameSite": "None"]) { _, new in new }
        )))
        let crossSite = (SyncJSON.value(none.readbackJSON) as? [[String: Any]])?.first?["sameSite"] as? String
        print("WebKit read back SameSite=None as \(crossSite ?? "nothing")")
        XCTAssertTrue(["None", "Unspecified"].contains(crossSite ?? ""), "WebKit read back SameSite=None as \(crossSite ?? "nothing")")

        let delete = await source.apply(SyncCookieOp(id: 2, isDelete: true, cookieJSON: #"{"domain":".example.com","path":"/","name":"sid"}"#))
        XCTAssertTrue(delete.ok)
        XCTAssertEqual(delete.readbackJSON, "[]")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertGreaterThan(changes, 0, "the cookie-store observer signals changes")
    }
}
