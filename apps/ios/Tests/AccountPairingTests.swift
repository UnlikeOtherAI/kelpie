import XCTest
@testable import Kelpie

@MainActor
final class AccountPairingTests: XCTestCase {
    private func body(_ fields: [String: Any] = [:]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["account": true, "clientId": "client", "clientName": "Client"].merging(fields) { _, new in new })
    }

    private func request(_ token: String, duplicate: Bool = false, source: String = "peer") -> ParsedHTTPRequest {
        ParsedHTTPRequest(method: "POST", path: "/v1/browser-control", query: "",
                          headers: ["authorization": duplicate ? ["Bearer \(token)", "Bearer other"] : ["Bearer \(token)"]],
                          body: Data(), sourceAddress: source, hasTransferEncoding: false)
    }

    private func connect(_ auth: AccountPairingAuthorization) async throws -> (challenge: String, token: String) {
        let started = await auth.handlePost(body: try body(), sourceAddress: "peer")
        XCTAssertEqual(started.status, 202)
        let challenge = try XCTUnwrap(started.json["requestId"] as? String)
        let approved = await auth.handlePost(body: try body(["requestId": challenge, "accountTicket": "proof"]), sourceAddress: "peer")
        XCTAssertEqual(approved.status, 200)
        XCTAssertEqual(approved.json["scope"] as? String, "session")
        return (challenge, try XCTUnwrap(approved.json["token"] as? String))
    }

    func testSameAccountIsAutomaticMemoryOnlyAndAlwaysRevalidated() async throws {
        let store = PairingStore(storeURL: nil)
        var checks = 0
        let auth = AccountPairingAuthorization(store: store, session: { "session" }, verify: { _, _, clientId, _ in
            checks += 1
            XCTAssertEqual(clientId, "client")
            return Date().timeIntervalSince1970 * 1_000 + 60_000
        })
        let connected = try await connect(auth)
        XCTAssertTrue(store.visiblePending().isEmpty)
        XCTAssertTrue(store.listPersistent().isEmpty)
        XCTAssertNil(store.validateBearer(connected.token), "Account grants cannot use the unverified manual path")
        let first = await auth.evaluate(request(connected.token))
        let second = await auth.evaluate(request(connected.token))
        XCTAssertEqual(first, .authenticated(clientId: "client"))
        XCTAssertEqual(second, first)
        let otherPeer = await auth.evaluate(request(connected.token, source: "another-peer"))
        guard case .reject(401, _, _) = otherPeer else { return XCTFail("Account bearer must stay source-bound") }
        XCTAssertEqual(checks, 3)
        XCTAssertNil(PairingStore(storeURL: nil).accountApproval(connected.token))
    }

    func testRevokedUoaAuthorityAndAccountChangesInvalidateAccess() async throws {
        let store = PairingStore(storeURL: nil)
        var session: String? = "original"
        var active = true
        let auth = AccountPairingAuthorization(store: store, session: { session }, verify: { _, _, _, _ in
            active ? Date().timeIntervalSince1970 * 1_000 + 60_000 : nil
        })
        let connected = try await connect(auth)
        active = false
        let revoked = await auth.evaluate(request(connected.token))
        guard case .reject(401, _, _) = revoked else { return XCTFail("UOA revocation must reject") }
        active = true
        for next in [nil, "another-session"] as [String?] {
            session = next
            let decision = await auth.evaluate(request(connected.token))
            guard case .reject(401, _, _) = decision else { return XCTFail("Account switch must reject") }
        }
    }

    func testChallengeCannotBeManuallyApprovedReplayedOrCollectedByAnotherPeer() async throws {
        let store = PairingStore(storeURL: nil)
        let auth = AccountPairingAuthorization(store: store, session: { "session" }, verify: { _, _, _, _ in
            Date().timeIntervalSince1970 * 1_000 + 60_000
        })
        let started = await auth.handlePost(body: try body(), sourceAddress: "peer")
        let challenge = try XCTUnwrap(started.json["requestId"] as? String)
        XCTAssertTrue(store.visiblePending().isEmpty)
        XCTAssertNil(store.approve(requestId: challenge, persist: true))
        let proof = try body(["requestId": challenge, "accountTicket": "proof"])
        let stolen = await auth.handlePost(body: proof, sourceAddress: "another-peer")
        XCTAssertEqual(stolen.status, 403)
        let accepted = await auth.handlePost(body: proof, sourceAddress: "peer")
        XCTAssertEqual(accepted.status, 200)
        let replay = await auth.handlePost(body: proof, sourceAddress: "peer")
        XCTAssertEqual(replay.status, 403)
        XCTAssertNil(store.takeIssuance(for: challenge, sourceAddress: "peer"))
        XCTAssertTrue(store.revoke(clientId: "client"))
        let suppressed = await auth.handlePost(body: try body(), sourceAddress: "peer")
        XCTAssertEqual(suppressed.status, 403)
    }

    func testSignOutDuringVerificationCannotIssueAccess() async throws {
        let store = PairingStore(storeURL: nil)
        var session: String? = "original"
        let auth = AccountPairingAuthorization(store: store, session: { session }, verify: { _, _, _, _ in
            session = nil
            return Date().timeIntervalSince1970 * 1_000 + 60_000
        })
        let started = await auth.handlePost(body: try body(), sourceAddress: "peer")
        let challenge = try XCTUnwrap(started.json["requestId"] as? String)
        let result = await auth.handlePost(body: try body(["requestId": challenge, "accountTicket": "proof"]), sourceAddress: "peer")
        XCTAssertEqual(result.status, 403)
        XCTAssertTrue(store.listSessions().isEmpty)
    }

    func testExpiredOverlongAndInvalidProofsNeverGrantAccess() async throws {
        for offset in [-1.0, 121_000.0] {
            let store = PairingStore(storeURL: nil)
            let auth = AccountPairingAuthorization(store: store, session: { "session" }, verify: { _, _, _, _ in
                Date().timeIntervalSince1970 * 1_000 + offset
            })
            let started = await auth.handlePost(body: try body(), sourceAddress: "peer")
            let challenge = try XCTUnwrap(started.json["requestId"] as? String)
            let result = await auth.handlePost(body: try body(["requestId": challenge, "accountTicket": "proof"]), sourceAddress: "peer")
            XCTAssertEqual(result.status, 403)
            XCTAssertTrue(store.listSessions().isEmpty)
        }
    }

    func testHeaderAmbiguityStillRejectsBeforeUoaVerification() async throws {
        let store = PairingStore(storeURL: nil)
        var checks = 0
        let auth = AccountPairingAuthorization(store: store, session: { "session" }, verify: { _, _, _, _ in
            checks += 1
            return Date().timeIntervalSince1970 * 1_000 + 60_000
        })
        let connected = try await connect(auth)
        let decision = await auth.evaluate(request(connected.token, duplicate: true))
        guard case .reject(400, _, _) = decision else { return XCTFail("Duplicate headers must reject") }
        XCTAssertEqual(checks, 1)
    }
}
