import WebKit
import XCTest
@testable import KelpieBrowser

/// The macOS sync adapter's write and read-back contract.
@MainActor
final class MacSyncCookieSourceTests: XCTestCase {
    private func cookie(_ name: String, domain: String, path: String = "/", value: String = "v",
                        expires: Date? = nil, secure: Bool = false, httpOnly: Bool = false) throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if let expires { properties[.expires] = expires }
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        return try XCTUnwrap(HTTPCookie(properties: properties))
    }

    private func decode(_ text: String) throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
    }

    private func op(_ id: Int, delete: Bool = false, _ json: [String: Any]) throws -> SyncCookieOp {
        let data = try JSONSerialization.data(withJSONObject: json)
        return SyncCookieOp(id: id, isDelete: delete, cookieJSON: try XCTUnwrap(String(bytes: data, encoding: .utf8)))
    }

    func testReadBackReturnsEverySameNamedCookieOnTheBareDomain() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let store = dataStore.httpCookieStore
        await store.setCookie(try cookie("sid", domain: "example.test", value: "host"))
        await store.setCookie(try cookie("sid", domain: "sub.example.test", value: "sub"))
        await store.setCookie(try cookie("other", domain: ".example.test"))

        let result = await MacSyncCookieSource.apply(try op(7, [
            "domain": ".example.test", "path": "/account", "name": "sid", "value": "wide", "expires": NSNull(),
            "secure": true, "httpOnly": true, "sameSite": "Lax"
        ]), to: .webKit(store))

        XCTAssertEqual(result.id, 7)
        XCTAssertTrue(result.ok)
        let readback = try decode(result.readbackJSON)
        XCTAssertEqual(Set(readback.compactMap { $0["value"] as? String }), ["host", "wide"])
        let written = try XCTUnwrap(readback.first { $0["value"] as? String == "wide" })
        XCTAssertEqual(written["httpOnly"] as? Bool, true)
        XCTAssertEqual(written["path"] as? String, "/account")
        XCTAssertEqual(written["sameSite"] as? String, "Lax")
        withExtendedLifetime(dataStore) {}
    }

    func testDeleteReadsBackWhatTheEngineStillHolds() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let store = dataStore.httpCookieStore
        await store.setCookie(try cookie("sid", domain: ".example.test"))
        await store.setCookie(try cookie("sid", domain: "example.test", value: "host"))

        let result = await MacSyncCookieSource.apply(
            try op(1, delete: true, ["domain": ".example.test", "path": "/", "name": "sid"]), to: .webKit(store)
        )

        XCTAssertTrue(result.ok)
        let readback = try decode(result.readbackJSON)
        XCTAssertEqual(readback.count, 1, "Only the domain cookie was the op's key")
        XCTAssertEqual(readback.first?["domain"] as? String, "example.test")
        withExtendedLifetime(dataStore) {}
    }

    func testMalformedOpReportsFailureWithoutTouchingTheEngine() async throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let store = dataStore.httpCookieStore
        let result = await MacSyncCookieSource.apply(SyncCookieOp(id: 3, isDelete: false, cookieJSON: "{"), to: .webKit(store))
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.readbackJSON, "[]")
        withExtendedLifetime(dataStore) {}
    }
}
