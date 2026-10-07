import XCTest
@testable import Kelpie

@MainActor
final class UOASessionTests: XCTestCase {
    private final class MemoryStorage: UOASessionStorage {
        var session: UOAStoredSession?
        init(_ session: UOAStoredSession? = nil) { self.session = session }
        func load() -> UOAStoredSession? { session }
        func save(_ session: UOAStoredSession) { self.session = session }
        func clear() { session = nil }
    }

    /// Scripted UOA. Each `/oauth/token` and `/oauth/me` call consumes the next reply.
    @MainActor
    private final class FakeUOA {
        struct Call { let path: String; let token: String?; let body: [String: Any] }
        var tokenReplies: [Result<String, Error>] = []
        var meStatuses: [Int] = []
        var tokenDelay: Duration = .zero
        /// When set, `/oauth/register` issues this client id; otherwise registration is unavailable.
        var registeredClientID: String?
        private(set) var calls: [Call] = []

        func calls(to path: String) -> [Call] { calls.filter { $0.path == path } }

        func request(_ path: String, _ method: String, _ token: String?, _ body: Data?, _ version: String?) async throws -> UOATransport.Response {
            let fields = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            calls.append(Call(path: path, token: token, body: fields))
            switch path {
            case "/oauth/token":
                try await Task.sleep(for: tokenDelay)
                return try reply(tokenReplies.removeFirst().get())
            case "/oauth/me":
                let status = meStatuses.isEmpty ? 200 : meStatuses.removeFirst()
                guard status == 200 else { throw UOATransport.Failure(status: status) }
                return reply(#"{"sub":"user-1","email":"person@example.com","name":"Person"}"#)
            case "/oauth/me/settings/browser/bookmarks": return reply(#"{"value":[]}"#)
            case "/oauth/revoke": return reply("{}")
            case "/oauth/register" where registeredClientID != nil:
                return reply(#"{"client_id":"\#(registeredClientID ?? "")"}"#)
            default: throw UOATransport.Failure(status: 503)
            }
        }

        private func reply(_ body: String) -> UOATransport.Response {
            UOATransport.Response(data: Data(body.utf8), version: "v1")
        }
    }

    private let stored = UOAStoredSession(clientID: "client-1", refreshToken: "refresh-1")

    private func grant(_ access: String, refresh: String?, expiresIn: Int = 1800) -> Result<String, Error> {
        let refreshField = refresh.map { #","refresh_token":"\#($0)""# } ?? ""
        return .success(#"{"access_token":"\#(access)","token_type":"Bearer","expires_in":\#(expiresIn)\#(refreshField)}"#)
    }

    /// Stands in for the login window: records what it was asked to open and lets the test end it.
    @MainActor
    private final class FakeLogin: UOALoginSurface {
        private(set) var url: URL?
        private(set) var closed = false
        private var finish: ((UOALoginResult) -> Void)?

        func present(_ url: URL, finish: @escaping (UOALoginResult) -> Void) -> UOALoginSurface? {
            self.url = url
            self.finish = finish
            return self
        }

        func end(_ result: UOALoginResult) { finish?(result) }
        func close() { closed = true }

        var state: String? {
            url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }?.first { $0.name == "state" }?.value
        }
    }

    private func makeAccount(_ server: FakeUOA, storage: MemoryStorage, login: FakeLogin? = nil) throws -> UOAAccount {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let presenter: UOALoginPresenter? = login.map { fake in { fake.present($0, finish: $1) } }
        return UOAAccount(transport: server.request, storage: storage, bookmarks: BookmarkStore(defaults: defaults), presentLogin: presenter)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Timed out waiting for the account state", file: file, line: line)
    }

    func testLaunchRestoreRotatesTheStoredSessionAndLoadsTheProfile() async throws {
        let server = FakeUOA()
        server.tokenReplies = [grant("access-1", refresh: "refresh-2")]
        let storage = MemoryStorage(stored)
        let account = try makeAccount(server, storage: storage)
        account.restoreSession()
        XCTAssertTrue(account.signingIn)
        await waitUntil { account.profile != nil }
        let refresh = try XCTUnwrap(server.calls(to: "/oauth/token").first)
        XCTAssertEqual(refresh.body["grant_type"] as? String, "refresh_token")
        XCTAssertEqual(refresh.body["refresh_token"] as? String, "refresh-1")
        XCTAssertEqual(refresh.body["client_id"] as? String, "client-1")
        XCTAssertEqual(storage.session, UOAStoredSession(clientID: "client-1", refreshToken: "refresh-2"))
        XCTAssertEqual(server.calls(to: "/oauth/me").first?.token, "access-1")
        XCTAssertEqual(account.profile?.email, "person@example.com")
        XCTAssertFalse(account.signingIn)
    }

    func testRejectedRestoreForgetsTheSessionAndReportsExpiry() async throws {
        let server = FakeUOA()
        server.tokenReplies = [.failure(UOATransport.Failure(status: 400))]
        let storage = MemoryStorage(stored)
        let account = try makeAccount(server, storage: storage)
        account.restoreSession()
        await waitUntil { !account.signingIn }
        XCTAssertNil(storage.session)
        XCTAssertNil(account.profile)
        XCTAssertEqual(account.error, UOATransport.Failure(status: 401).localizedDescription)
    }

    func testRestoreFailingInTransitKeepsTheSessionForTheNextAttempt() async throws {
        let server = FakeUOA()
        server.tokenReplies = [.failure(URLError(.notConnectedToInternet)), .failure(UOATransport.Failure(status: 503))]
        let storage = MemoryStorage(stored)
        let account = try makeAccount(server, storage: storage)
        account.restoreSession()
        await waitUntil { !account.signingIn }
        XCTAssertEqual(storage.session, stored)
        XCTAssertNil(account.profile)
        XCTAssertNotNil(account.error)
        account.signIn()
        await waitUntil { !account.signingIn }
        XCTAssertEqual(storage.session, stored)
        XCTAssertTrue(server.calls(to: "/oauth/register").isEmpty, "A transient failure must not start interactive sign-in")
    }

    func testSignInFallsBackToInteractiveLoginOnlyWhenTheStoredSessionIsRejected() async throws {
        let server = FakeUOA()
        server.tokenReplies = [.failure(UOATransport.Failure(status: 401))]
        let storage = MemoryStorage(stored)
        let account = try makeAccount(server, storage: storage)
        account.signIn()
        await waitUntil { !account.signingIn }
        XCTAssertNil(storage.session)
        XCTAssertEqual(server.calls(to: "/oauth/register").count, 1)
    }

    func testNearlyExpiredAccessTokenIsRefreshedBeforeUse() async throws {
        let server = FakeUOA()
        server.tokenReplies = [grant("access-1", refresh: "refresh-2", expiresIn: 30), grant("access-2", refresh: "refresh-3")]
        let storage = MemoryStorage(stored)
        let account = try makeAccount(server, storage: storage)
        account.restoreSession()
        await waitUntil { account.profile != nil }
        XCTAssertEqual(server.calls(to: "/oauth/token").map { $0.body["refresh_token"] as? String }, ["refresh-1", "refresh-2"])
        XCTAssertEqual(server.calls(to: "/oauth/me").first?.token, "access-2")
        XCTAssertEqual(storage.session?.refreshToken, "refresh-3")
    }

    func testRefusedAccessTokenIsRotatedOnceAndTheRequestRetried() async throws {
        let server = FakeUOA()
        server.tokenReplies = [grant("access-1", refresh: "refresh-2"), grant("access-2", refresh: "refresh-3")]
        server.meStatuses = [401, 200]
        let storage = MemoryStorage(stored)
        let account = try makeAccount(server, storage: storage)
        account.restoreSession()
        await waitUntil { account.profile != nil }
        XCTAssertEqual(server.calls(to: "/oauth/me").map(\.token), ["access-1", "access-2"])
        XCTAssertEqual(storage.session?.refreshToken, "refresh-3")
    }

    func testSignOutForgetsTheSessionAndRevokesIt() async throws {
        let server = FakeUOA()
        server.tokenReplies = [grant("access-1", refresh: "refresh-2")]
        let storage = MemoryStorage(stored)
        let account = try makeAccount(server, storage: storage)
        account.restoreSession()
        await waitUntil { account.profile != nil }
        account.signOut()
        XCTAssertNil(storage.session)
        XCTAssertNil(account.profile)
        await waitUntil { !server.calls(to: "/oauth/revoke").isEmpty }
        let revoke = try XCTUnwrap(server.calls(to: "/oauth/revoke").first)
        XCTAssertEqual(revoke.body["token"] as? String, "refresh-2")
        XCTAssertEqual(revoke.body["client_id"] as? String, "client-1")
    }

    func testServerWithoutRefreshTokensKeepsTheSessionInMemoryOnly() async throws {
        let server = FakeUOA()
        server.tokenReplies = [grant("access-1", refresh: nil)]
        let storage = MemoryStorage(stored)
        let account = try makeAccount(server, storage: storage)
        account.restoreSession()
        await waitUntil { account.profile != nil }
        XCTAssertNil(storage.session)
    }

    func testRestoreFinishingAfterSignOutNeverWritesStorage() async throws {
        let server = FakeUOA()
        server.tokenDelay = .milliseconds(80)
        server.tokenReplies = [grant("access-1", refresh: "refresh-2")]
        let storage = MemoryStorage(stored)
        let account = try makeAccount(server, storage: storage)
        account.restoreSession()
        await waitUntil { !server.calls(to: "/oauth/token").isEmpty }
        account.signOut()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(storage.session)
        XCTAssertNil(account.profile)
        XCTAssertFalse(account.signingIn)
    }

    func testInteractiveLoginExchangesTheInterceptedCallbackForASession() async throws {
        let server = FakeUOA()
        server.registeredClientID = "client-9"
        server.tokenReplies = [grant("access-1", refresh: "refresh-9")]
        let storage = MemoryStorage()
        let login = FakeLogin()
        let account = try makeAccount(server, storage: storage, login: login)
        account.signIn()
        await waitUntil { login.url != nil }
        XCTAssertEqual(login.url?.host, URL(string: UOATransport.origin)?.host)
        let state = try XCTUnwrap(login.state)
        login.end(.callback(try XCTUnwrap(URL(string: UOAAuthorization.callback + "?code=code-1&state=" + state))))
        await waitUntil { account.profile != nil }
        let exchange = try XCTUnwrap(server.calls(to: "/oauth/token").first)
        XCTAssertEqual(exchange.body["grant_type"] as? String, "authorization_code")
        XCTAssertEqual(exchange.body["code"] as? String, "code-1")
        XCTAssertEqual(exchange.body["client_id"] as? String, "client-9")
        XCTAssertEqual(exchange.body["redirect_uri"] as? String, UOAAuthorization.callback)
        XCTAssertNotNil(exchange.body["code_verifier"] as? String)
        XCTAssertEqual(storage.session, UOAStoredSession(clientID: "client-9", refreshToken: "refresh-9"))
        XCTAssertFalse(account.signingIn)
    }

    func testCallbackWithAForeignStateIsRejected() async throws {
        let server = FakeUOA()
        server.registeredClientID = "client-9"
        let login = FakeLogin()
        let account = try makeAccount(server, storage: MemoryStorage(), login: login)
        account.signIn()
        await waitUntil { login.url != nil }
        login.end(.callback(try XCTUnwrap(URL(string: UOAAuthorization.callback + "?code=code-1&state=forged"))))
        await waitUntil { !account.signingIn }
        XCTAssertNil(account.profile)
        XCTAssertNotNil(account.error)
        XCTAssertTrue(server.calls(to: "/oauth/token").isEmpty)
    }

    func testCancellingTheLoginLeavesTheAccountSignedOutWithoutAnError() async throws {
        let server = FakeUOA()
        server.registeredClientID = "client-9"
        let login = FakeLogin()
        let account = try makeAccount(server, storage: MemoryStorage(), login: login)
        account.signIn()
        await waitUntil { login.url != nil }
        login.end(.cancelled)
        XCTAssertFalse(account.signingIn)
        XCTAssertNil(account.profile)
        XCTAssertNil(account.error)
        XCTAssertTrue(server.calls(to: "/oauth/token").isEmpty)
    }

    func testSignOutClosesAnOpenLoginAndIgnoresItsLateCallback() async throws {
        let server = FakeUOA()
        server.registeredClientID = "client-9"
        let login = FakeLogin()
        let account = try makeAccount(server, storage: MemoryStorage(), login: login)
        account.signIn()
        await waitUntil { login.url != nil }
        let state = try XCTUnwrap(login.state)
        account.cancelSignIn()
        XCTAssertTrue(login.closed)
        login.end(.callback(try XCTUnwrap(URL(string: UOAAuthorization.callback + "?code=code-1&state=" + state))))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(account.profile)
        XCTAssertFalse(account.signingIn)
        XCTAssertTrue(server.calls(to: "/oauth/token").isEmpty)
    }
}
