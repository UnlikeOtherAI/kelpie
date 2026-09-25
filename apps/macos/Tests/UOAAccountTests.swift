import XCTest
@testable import Kelpie

@MainActor
final class UOAAccountTests: XCTestCase {
    func testPKCEUsesRFC7636Challenge() throws {
        let authorization = UOAAuthorization(state: "state", verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(authorization.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(try authorization.code(from: XCTUnwrap(URL(string: UOAAuthorization.callback + "?state=state&code=one"))), "one")
        for suffix in ["?state=other&code=one", "?state=state&state=state&code=one", "?state=state&code=one&code=two", "?state=state&code=one#error"] {
            XCTAssertThrowsError(try authorization.code(from: XCTUnwrap(URL(string: UOAAuthorization.callback + suffix))))
        }
        XCTAssertThrowsError(try authorization.code(from: XCTUnwrap(URL(string: "https://oauth/callback?state=state&code=one"))))
    }

    func testConflictRetriesIntentAgainstLatestListWithoutPersistingAccountData() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let store = BookmarkStore(defaults: defaults)
        store.add(title: "Local", url: "https://local.example")
        let added = BookmarkStore.Bookmark(title: "Added", url: "https://added.example")
        let other = BookmarkStore.Bookmark(title: "Other device", url: "https://other.example")
        var puts = 0
        var current: [BookmarkStore.Bookmark] = []
        let sync = AccountBookmarks(store: store) { _, method, body, _ in
            if method == "PUT" {
                puts += 1
                if puts == 1 { current = [other]; throw UOATransport.Failure(status: 409) }
                struct Envelope: Decodable { let value: [BookmarkStore.Bookmark] }
                let saved = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any]
                let values = saved?["value"] as? [[String: Any]]
                XCTAssertEqual(values?.first?["favicon"] as? String, "https://other.example/favicon.png")
                current = try JSONDecoder().decode(Envelope.self, from: XCTUnwrap(body)).value
            }
            struct Envelope: Encodable { let value: [BookmarkStore.Bookmark] }
            let encoded = try JSONEncoder().encode(Envelope(value: current))
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            var values = object["value"] as? [[String: Any]] ?? []
            if !values.isEmpty { values[0]["favicon"] = "https://other.example/favicon.png" }
            object["value"] = values
            return UOATransport.Response(data: try JSONSerialization.data(withJSONObject: object), version: "version")
        }
        sync.enqueue(.add(added))
        try await sync.flush()
        XCTAssertEqual(puts, 2)
        XCTAssertEqual(store.bookmarks.map(\.url), [other.url, added.url])
        XCTAssertEqual(BookmarkStore(defaults: defaults).bookmarks.map(\.url), ["https://local.example"])
    }

    func testFailedSaveDoesNotPublishSuccessAndInvalidatedResponseCannotReplaceLocalList() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let store = BookmarkStore(defaults: defaults)
        store.add(title: "Local", url: "https://local.example")
        let sync = AccountBookmarks(store: store) { _, _, _, _ in throw UOATransport.Failure(status: 503) }
        sync.enqueue(.clear)
        try? await sync.flush()
        XCTAssertNotNil(store.syncError)
        XCTAssertEqual(store.bookmarks.count, 1)
        let delayed = AccountBookmarks(store: store) { _, _, _, _ in
            try await Task.sleep(for: .milliseconds(20))
            return UOATransport.Response(data: Data("{\"value\":[]}".utf8), version: "version")
        }
        delayed.enqueue()
        await Task.yield()
        delayed.invalidate()
        try? await delayed.flush()
        XCTAssertEqual(store.bookmarks.count, 1)
    }

    func testAndroidDatesRoundTripAndEachSaveKeepsItsOwnFailure() async throws {
        let raw = Data(#"{"url":"https://android.example","createdAt":"2026-09-25T10:20:30.123Z"}"#.utf8)
        let bookmark = try JSONDecoder().decode(BookmarkStore.Bookmark.self, from: raw)
        XCTAssertGreaterThan(bookmark.createdAt.timeIntervalSince1970, 1_700_000_000)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(bookmark)) as? [String: Any]
        XCTAssertTrue((encoded?["createdAt"] as? String)?.hasSuffix("Z") == true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let store = BookmarkStore(defaults: defaults)
        var puts = 0
        let sync = AccountBookmarks(store: store) { _, method, body, _ in
            if method == "PUT" {
                puts += 1
                if puts == 1 { throw UOATransport.Failure(status: 503) }
                return UOATransport.Response(data: try XCTUnwrap(body), version: "v2")
            }
            return UOATransport.Response(data: Data(#"{"value":[]}"#.utf8), version: "v1")
        }
        let failed = sync.enqueue(.clear)
        let saved = sync.enqueue(.add(bookmark))
        do { try await failed.value; XCTFail("The first save must fail") } catch { }
        try await saved.value
        do { try await failed.value; XCTFail("A later save must not hide the failure") } catch { }
    }
}
