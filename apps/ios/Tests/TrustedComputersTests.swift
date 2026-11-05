import XCTest
@testable import Kelpie

final class TrustedComputersTests: XCTestCase {
    private var directory: URL!
    private var store: PairingStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = PairingStore(storeURL: directory.appendingPathComponent("pairings.json"))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func request(source: String, headers: [String: [String]] = [:]) -> ParsedHTTPRequest {
        ParsedHTTPRequest(
            method: "POST", path: "/v1/browser-control", query: "",
            headers: ["host": ["127.0.0.1:8420"], "content-type": ["application/json"]].merging(headers) { _, new in new },
            body: Data("{}".utf8), sourceAddress: source, hasTransferEncoding: false
        )
    }

    func testLoopbackNeedsNoTokenButCannotAuthorizeAWebpage() {
        let auth = AuthMiddleware(store: store)
        for source in ["127.0.0.1", "127.2.3.4", "::1", "[::ffff:127.0.0.1]"] {
            guard case .authenticated = auth.evaluate(request(source: source)) else { return XCTFail("Localhost must be trusted") }
        }
        for headers in [["origin": ["null"]], ["host": ["evil.example"]], ["sec-fetch-site": ["cross-site"]]] {
            guard case .reject(403, _, _) = auth.evaluate(request(source: "127.0.0.1", headers: headers)) else {
                return XCTFail("Browser requests cannot inherit localhost permission")
            }
        }
        let duplicate = request(source: "127.0.0.1", headers: ["authorization": ["Bearer a", "Bearer b"]])
        guard case .reject(400, _, _) = auth.evaluate(duplicate) else { return XCTFail("Framing checks precede trust") }
    }

    func testOneDecisionResolvesIndependentCallersAndSurvivesRestart() throws {
        let source = "192.0.2.10"
        let auth = AuthMiddleware(store: store)
        guard case .reject(401, _, _) = auth.evaluate(request(source: source)) else { return XCTFail("Unknown remote must need approval") }
        guard case .created(let first) = store.startPairing(clientId: "same", clientName: "First", sourceAddress: source),
              case .created(let second) = store.startPairing(clientId: "same", clientName: "Second", sourceAddress: "::ffff:192.0.2.10"),
              case .created(let account) = store.startPairing(clientId: "account", clientName: "Account", sourceAddress: source, accountSession: "uoa") else {
            return XCTFail("Could not create independent requests")
        }
        XCTAssertNotEqual(first.requestId, second.requestId)
        XCTAssertEqual(store.visiblePending().count, 1)
        XCTAssertNil(store.approve(requestId: account.requestId, persist: true))
        XCTAssertTrue(store.trustedComputers.list().isEmpty)
        XCTAssertNotNil(store.approve(requestId: first.requestId, persist: true))
        XCTAssertNotNil(store.takeIssuance(for: first.requestId, sourceAddress: source))
        XCTAssertNotNil(store.takeIssuance(for: second.requestId, sourceAddress: source))
        XCTAssertNotNil(store.pendingRequest(requestId: account.requestId), "Manual approval must not resolve an account challenge")
        XCTAssertTrue(store.listPersistent().isEmpty, "Host permissions do not create legacy client records")
        let restarted = PairingStore(storeURL: directory.appendingPathComponent("pairings.json"))
        XCTAssertEqual(restarted.trustedComputers.list().map(\.address), [source])
        XCTAssertEqual(AuthMiddleware(store: restarted).evaluate(request(source: source)), .authenticated(clientId: "host:\(source)", computerAddress: source))
        XCTAssertTrue(restarted.revokeComputer(address: source))
        guard case .reject(401, _, _) = auth.evaluate(request(source: source)) else { return XCTFail("Existing processes must observe revocation") }
        guard case .authenticated = auth.evaluate(request(source: "127.0.0.1")) else { return XCTFail("Localhost stays trusted") }
    }

    func testExplicitPairingFromTrustedComputerHasNoPromptAndCannotMoveToAnotherIP() throws {
        XCTAssertTrue(store.trustedComputers.approve(address: "192.0.2.10", name: "Computer"))
        let endpoints = PairEndpoints(store: store, onPendingChanged: nil)
        let data = try JSONSerialization.data(withJSONObject: ["clientId": "new", "clientName": "New process"])
        let started = endpoints.handlePairPost(body: data, sourceAddress: "192.0.2.10")
        XCTAssertEqual(started.json["approvalRequired"] as? Bool, false)
        XCTAssertTrue(store.visiblePending().isEmpty)
        let id = try XCTUnwrap(started.json["requestId"] as? String)
        let stolen = endpoints.handlePairStatus(query: "requestId=\(id)", sourceAddress: "192.0.2.11")
        XCTAssertEqual(stolen.json["status"] as? String, "not_found")
        let approved = endpoints.handlePairStatus(query: "requestId=\(id)", sourceAddress: "192.0.2.10")
        let token = try XCTUnwrap(approved.json["token"] as? String)
        let foreign = request(source: "192.0.2.11", headers: ["authorization": ["Bearer \(token)"]])
        guard case .reject(401, _, _) = AuthMiddleware(store: store).evaluate(foreign) else { return XCTFail("Host-issued token cannot authorize another IP") }
    }

    func testFailedPersistenceKeepsPromptPendingAndDoesNotGrantAccess() throws {
        let path = directory.appendingPathComponent("trusted-computers.json")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        guard case .created(let pending) = store.startPairing(clientId: "a", clientName: "A", sourceAddress: "192.0.2.10") else {
            return XCTFail("Could not create request")
        }
        XCTAssertNil(store.approve(requestId: pending.requestId, persist: true))
        XCTAssertEqual(store.visiblePending().count, 1)
        XCTAssertNil(store.trustedComputers.clientId(for: "192.0.2.10"))
    }
    func testClientIdsCannotRevokeComputerAuthorityAndLegacyTokensStillWork() throws {
        let victim = "192.0.2.11"
        XCTAssertTrue(store.trustedComputers.approve(address: victim, name: "Other computer"))
        guard case .created(let pending) = store.startPairing(clientId: "host:\(victim)", clientName: "Legacy", sourceAddress: "192.0.2.10") else {
            return XCTFail("Could not create legacy session")
        }
        let token = try XCTUnwrap(store.approve(requestId: pending.requestId, persist: false)?.token)
        XCTAssertTrue(store.trustedComputers.approve(address: "192.0.2.10", name: "Computer"))
        let legacy = request(source: "192.0.2.10", headers: ["host": ["custom-alias.local"], "authorization": ["Bearer \(token)"]])
        XCTAssertEqual(AuthMiddleware(store: store).evaluate(legacy), .authenticated(clientId: "host:\(victim)"))
        XCTAssertTrue(store.revoke(clientId: "host:\(victim)"))
        XCTAssertNotNil(store.trustedComputers.clientId(for: victim))
        XCTAssertNil(store.validateBearer(token))
    }

    func testSourceCannotFillEveryOtherComputersQueueAndApprovalOverridesSuppression() throws {
        for index in 0..<32 {
            guard case .created = store.startPairing(clientId: "client-\(index)", clientName: "Client", sourceAddress: "192.0.2.10") else {
                return XCTFail("Normal concurrent callers need independent challenges")
            }
        }
        guard case .rateLimited = store.startPairing(clientId: "overflow", clientName: "Client", sourceAddress: "192.0.2.10") else {
            return XCTFail("Source limit must be explicit")
        }
        guard case .created(let other) = store.startPairing(clientId: "other", clientName: "Other", sourceAddress: "192.0.2.11") else {
            return XCTFail("One source cannot fill another computer's queue")
        }
        store.deny(requestId: other.requestId)
        XCTAssertTrue(store.wasRecentlyDenied(sourceAddress: "::ffff:192.0.2.11"))
        XCTAssertTrue(store.trustedComputers.approve(address: "192.0.2.11", name: "Approved elsewhere"))
        guard case .created = store.startPairing(clientId: "new", clientName: "New", sourceAddress: "192.0.2.11") else {
            return XCTFail("An approved computer must not remain suppressed")
        }
    }

    func testComputerRevocationPreservesAnIndependentAccountIssuance() throws {
        let source = "192.0.2.10"
        XCTAssertTrue(store.trustedComputers.approve(address: source, name: "Computer"))
        guard case .created(let pending) = store.startPairing(clientId: "account", clientName: "Account", sourceAddress: source, accountSession: "uoa") else {
            return XCTFail("Could not create account request")
        }
        XCTAssertNil(store.approve(requestId: pending.requestId, persist: true))
        let grant = PairingStore.AccountGrant(session: "uoa", ticket: "verified-proof", challenge: pending.requestId,
                                             expiresAt: Date().timeIntervalSince1970 * 1_000 + 60_000, sourceAddress: source)
        XCTAssertNotNil(store.approve(requestId: pending.requestId, persist: false, accountGrant: grant))
        XCTAssertTrue(store.revokeComputer(address: source))
        XCTAssertNotNil(store.takeIssuance(for: pending.requestId, sourceAddress: source))
    }

    func testCorruptStoreRecoversOnlyAfterExplicitApproval() throws {
        let path = directory.appendingPathComponent("trusted-computers.json")
        try Data("corrupt".utf8).write(to: path)
        XCTAssertNil(store.trustedComputers.clientId(for: "192.0.2.10"))
        guard case .created(let pending) = store.startPairing(clientId: "fresh", clientName: "Fresh", sourceAddress: "192.0.2.10") else {
            return XCTFail("Could not create recovery request")
        }
        XCTAssertNotNil(store.approve(requestId: pending.requestId, persist: true))
        XCTAssertEqual(store.trustedComputers.list().map(\.address), ["192.0.2.10"])
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("trusted-computers.json.corrupt-") })
    }

}
