import WebKit
import XCTest
@testable import KelpieBrowser

/// Argument validation and default-store behaviour of the agent cookie endpoints.
@MainActor
final class CookieEndpointTests: XCTestCase {
    private let domain = "kelpie-cookie-endpoint-\(UUID().uuidString.lowercased()).test"
    private var handler: BrowserManagementHandler!

    override func setUp() async throws {
        handler = BrowserManagementHandler(context: HandlerContext(), viewportState: ViewportState())
    }

    override func tearDown() async throws {
        let store = KelpieWebsiteData.store.httpCookieStore
        for cookie in await store.allCookies() where cookie.domain.hasSuffix(domain) {
            await store.deleteCookie(cookie)
        }
    }

    private func expect(_ code: String, _ response: [String: Any], line: UInt = #line) {
        XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? String, code, line: line)
    }

    func testSetCookiesRequiresABoundedArray() async {
        expect("INVALID_ARGUMENT", await handler.setCookies([:]))
        expect("INVALID_ARGUMENT", await handler.setCookies(["cookies": "sid=1"]))
        let tooMany = Array(repeating: ["name": "n", "value": "v", "domain": domain] as [String: Any], count: 501)
        expect("INVALID_ARGUMENT", await handler.setCookies(["cookies": tooMany]))
    }

    func testTargetsNameOneStore() async {
        let both: [String: Any] = ["cookies": [Any](), "tabId": UUID().uuidString, "partition": "work"]
        expect("INVALID_ARGUMENT", await handler.setCookies(both))
        expect("INVALID_ARGUMENT", await handler.getCookies(["all": "yes"]))
        expect("INVALID_PARTITION", await handler.getCookies(["partition": "bad id!"]))
        expect("PARTITION_NOT_FOUND", await handler.getCookies(["partition": "never-created-\(UUID().uuidString)"]))
        expect("TAB_NOT_FOUND", await handler.getCookies(["all": true, "tabId": UUID().uuidString]))
    }

    func testCopyCookiesRefusesTheSameStoreAndMalformedEnds() async {
        expect("INVALID_ARGUMENT", await handler.copyCookies([:]))
        expect("INVALID_ARGUMENT", await handler.copyCookies(["from": [String: Any](), "to": [String: Any]()]))
        expect("INVALID_ARGUMENT", await handler.copyCookies(["from": "default", "to": [String: Any]()]))
        expect("INVALID_PARTITION", await handler.copyCookies(["to": ["partition": "bad id!"]]))
    }

    func testSetCookiesReportsEachRejectedCookieWithoutItsValue() async throws {
        let response = await handler.setCookies(["cookies": [
            ["name": "sid", "value": "secret", "domain": ".\(domain)", "httpOnly": true, "secure": true,
             "sameSite": "Lax", "expires": 2_000_000_000],
            ["name": "", "value": "x", "domain": domain],
            ["name": "bad", "value": "x", "domain": domain, "sameSite": "lenient"],
            ["name": "bad", "value": "x", "domain": domain, "expires": "next tuesday"]
        ]])
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(response["set"] as? Int, 1)
        let failed = try XCTUnwrap(response["failed"] as? [[String: Any]])
        XCTAssertEqual(failed.compactMap { $0["index"] as? Int }, [1, 2, 3])
        XCTAssertEqual(Set(failed.compactMap { $0["error"] as? String }), ["INVALID_COOKIE"])
        XCTAssertFalse(failed.contains { $0["value"] != nil })
    }

    func testDefaultStoreRoundTripThroughGetCookiesAll() async throws {
        let session = ["name": "session", "value": "s", "domain": ".\(domain)", "httpOnly": true, "secure": true] as [String: Any]
        let host = ["name": "pref", "value": "p", "domain": "app.\(domain)", "sameSite": "Strict",
                    "expires": "2027-05-18T03:33:20Z"] as [String: Any]
        let stored = await handler.setCookies(["cookies": [session, host]])
        XCTAssertEqual(stored["set"] as? Int, 2)

        let read = await handler.getCookies(["all": true, "domain": domain])
        XCTAssertEqual(read["complete"] as? Bool, true)
        let cookies = try XCTUnwrap(read["cookies"] as? [[String: Any]])
        let byName = Dictionary(uniqueKeysWithValues: cookies.compactMap { cookie in (cookie["name"] as? String).map { ($0, cookie) } })
        XCTAssertEqual(byName["session"]?["httpOnly"] as? Bool, true)
        XCTAssertTrue(byName["session"]?["expires"] is NSNull)
        // WebKit reads a cookie stored without SameSite back as None on newer macOS.
        XCTAssertTrue(["Unspecified", "None"].contains(byName["session"]?["sameSite"] as? String ?? ""))
        XCTAssertEqual(byName["pref"]?["domain"] as? String, "app.\(domain)")
        XCTAssertEqual(byName["pref"]?["sameSite"] as? String, "Strict")

        // The get-cookies output is accepted back by set-cookies.
        let again = await handler.setCookies(["cookies": cookies])
        XCTAssertEqual(again["set"] as? Int, 2)
        let subdomainOnly = await handler.getCookies(["all": true, "domain": "app.\(domain)"])
        XCTAssertEqual((subdomainOnly["cookies"] as? [[String: Any]])?.compactMap { $0["name"] as? String }, ["pref"])
    }
}
