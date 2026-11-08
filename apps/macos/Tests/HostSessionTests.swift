import XCTest
@testable import KelpieBrowser

@MainActor
final class HostSessionTests: XCTestCase {
    private final class Storage: UOASessionStorage {
        var reads = 0
        var writes = 0
        var clears = 0
        func load() -> UOAStoredSession? { reads += 1; return nil }
        func save(_ session: UOAStoredSession) { writes += 1 }
        func clear() { clears += 1 }
    }

    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }

    func testEmbeddedAccountUsesOnlyTheHostSession() async throws {
        let storage = Storage()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let account = UOAAccount(storage: storage, bookmarks: BookmarkStore(defaults: defaults))
        var signIns = 0
        var signOuts = 0
        let host = KelpieUOASession(
            subject: "person",
            request: { path, _, _, _ in
                if path == "/oauth/me" {
                    return .init(data: Data(#"{"sub":"person","email":"person@example.test"}"#.utf8))
                }
                if path == "/oauth/me/settings/browser/bookmarks" {
                    return .init(data: Data(#"{"value":[]}"#.utf8), version: "v1")
                }
                throw UOATransport.Failure(status: 404)
            },
            settingsSocket: { _, _ in throw UOATransport.Failure(status: 503) },
            signIn: { signIns += 1 },
            signOut: { signOuts += 1 }
        )
        account.useHostSession(host)
        account.restoreSession()
        await settle { account.profile != nil }
        XCTAssertEqual(account.profile?.sub, "person")
        account.signOut()
        XCTAssertNil(account.profile)
        account.signIn()
        XCTAssertEqual(signOuts, 1)
        XCTAssertEqual(signIns, 1)
        XCTAssertEqual(storage.reads, 0)
        XCTAssertEqual(storage.writes, 0)
        XCTAssertEqual(storage.clears, 0)
    }

    func testHostHTTPConflictKeepsTheStatusUsedByBookmarkRecovery() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let account = UOAAccount(storage: Storage(), bookmarks: BookmarkStore(defaults: defaults))
        let host = KelpieUOASession(
            subject: nil,
            request: { _, _, _, _ in throw KelpieUOASession.Failure(status: 409) },
            settingsSocket: { _, _ in throw KelpieUOASession.Failure(status: 503) },
            signIn: {}, signOut: {}
        )
        account.useHostSession(host)
        do {
            _ = try await account.request("/oauth/me/settings/browser/bookmarks", method: "PUT")
            XCTFail("A conflicting host write must fail")
        } catch let failure as UOATransport.Failure {
            XCTAssertEqual(failure.status, 409)
        }
    }

    func testHostIdentityReplacementRejectsAnOldResponse() async throws {
        let storage = Storage()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let account = UOAAccount(storage: storage, bookmarks: BookmarkStore(defaults: defaults))
        var release: CheckedContinuation<Void, Never>?
        let host = KelpieUOASession(
            subject: "person",
            request: { path, _, _, _ in
                if path == "/oauth/me" {
                    await withCheckedContinuation { release = $0 }
                    return .init(data: Data(#"{"sub":"person","email":"person@example.test"}"#.utf8))
                }
                throw UOATransport.Failure(status: 404)
            },
            settingsSocket: { _, _ in throw UOATransport.Failure(status: 503) },
            signIn: {},
            signOut: {}
        )
        account.useHostSession(host)
        await settle { release != nil }
        host.update(subject: nil)
        release?.resume()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertNil(account.profile)
        XCTAssertEqual(storage.reads, 0)
        XCTAssertEqual(storage.writes, 0)
        XCTAssertEqual(storage.clears, 0)
    }
}
