import Network
import XCTest
@testable import KelpieBrowser

final class SyncListenerAdmissionTests: XCTestCase {
    // MARK: - Address rule

    private let rule = SyncAddressRule {
        [
            .init(name: "en0", address: [192, 168, 1, 10], netmask: [255, 255, 255, 0]),
            .init(name: "en0", address: [0x20, 0x01, 0x0d, 0xb8] + [UInt8](repeating: 0, count: 11) + [1],
                  netmask: [UInt8](repeating: 0xff, count: 8) + [UInt8](repeating: 0, count: 8))
        ]
    }

    private func host(_ text: String) -> NWEndpoint.Host { NWEndpoint.Host(text) }

    func testAddressRuleAllowsLoopbackLinkLocalAndConnectedSubnetsOnly() {
        for allowed in ["127.0.0.1", "127.8.9.10", "169.254.3.4", "192.168.1.42", "::1", "fe80::1", "2001:db8::5", "::ffff:192.168.1.7"] {
            XCTAssertTrue(rule.allows(host(allowed)), allowed)
        }
        for refused in ["10.0.0.5", "192.168.2.1", "8.8.8.8", "2001:db8:1::5", "2606:4700::1111"] {
            XCTAssertFalse(rule.allows(host(refused)), refused)
        }
        XCTAssertFalse(rule.allows(.name("peer.local", nil)))
        XCTAssertFalse(rule.allows(.service(name: "x", type: "_kelpie-sync._tcp", domain: "local.", interface: nil)))
    }

    func testOnlyPhysicalWiFiAndEthernetInterfacesAreEligible() {
        XCTAssertTrue(SyncAddressRule.isEligible(name: "en0"))
        XCTAssertTrue(SyncAddressRule.isEligible(name: "en7"))
        for name in ["utun3", "ipsec0", "ppp0", "pdp_ip0", "awdl0", "llw0", "bridge0", "lo0", "gif0"] {
            XCTAssertFalse(SyncAddressRule.isEligible(name: name), name)
        }
        XCTAssertTrue(SyncAddressRule.eligibleInterfaces().allSatisfy { SyncAddressRule.isEligible(name: $0.name) })
    }

    // MARK: - Static admission

    private func head(_ lines: [String], method: String = "POST", path: String = "/v1/sync/hello") -> SyncHTTPHead {
        let text = (["\(method) \(path) HTTP/1.1"] + lines).joined(separator: "\r\n")
        return SyncHTTPHead.parse(Data(text.utf8)) ?? SyncHTTPHead(method: "", path: "", headers: [:])
    }

    private func refusal(_ head: SyncHTTPHead) -> Int? {
        guard case .failure(let refusal) = SyncListener.check(head) else { return nil }
        return refusal.response.status
    }

    func testHeadChecksRunBeforeAnyBodyIsRead() {
        let json = "Content-Type: application/json"
        XCTAssertNil(refusal(head([json, "Content-Length: 10"])))
        XCTAssertNil(refusal(head(["Content-Type: application/json; charset=utf-8", "Content-Length: 10"])))
        XCTAssertEqual(refusal(head([json, "Content-Length: 10"], method: "GET")), 405)
        XCTAssertEqual(refusal(head([json, "Content-Length: 10"], path: "/v1/get-cookies")), 404)
        XCTAssertEqual(refusal(head([json, "Content-Length: 10", "Origin: https://evil.example"])), 403)
        XCTAssertEqual(refusal(head([json, "Content-Length: 10", "Transfer-Encoding: chunked"])), 400)
        XCTAssertEqual(refusal(head([json, "Content-Length: 10", "Content-Length: 10"])), 400)
        XCTAssertEqual(refusal(head([json])), 411)
        XCTAssertEqual(refusal(head([json, "Content-Length: -1"])), 400)
        XCTAssertEqual(refusal(head(["Content-Type: text/plain", "Content-Length: 10"])), 415)
        XCTAssertEqual(refusal(head([json, "Content-Length: 16385"])), 413)
        XCTAssertNil(refusal(head([json, "Content-Length: 16384"], path: "/v1/sync/auth")))
        XCTAssertNil(refusal(head([json, "Content-Length: 4194304"], path: "/v1/sync/exchange")))
        XCTAssertEqual(refusal(head([json, "Content-Length: 4194305"], path: "/v1/sync/exchange")), 413)
    }

    // MARK: - Replay window

    func testReplayWindowAcceptsEachSeqOnceWithin64OfTheHighest() {
        var window = SyncReplayWindow()
        XCTAssertFalse(window.canAccept(0))
        for seq: UInt64 in [1, 3, 2] {
            XCTAssertTrue(window.canAccept(seq))
            window.mark(seq)
            XCTAssertFalse(window.canAccept(seq), "seq \(seq) replayed")
        }
        window.mark(70)
        XCTAssertFalse(window.canAccept(5), "more than 64 below the highest")
        XCTAssertTrue(window.canAccept(6), "exactly 64 below the highest")
        window.mark(6)
        XCTAssertFalse(window.canAccept(6))
        XCTAssertTrue(window.canAccept(69))
        XCTAssertFalse(window.canAccept(70))
        window.mark(200)
        XCTAssertFalse(window.canAccept(70))
        XCTAssertTrue(window.canAccept(199))
    }

    // MARK: - Live listener

    private func startListener() async throws -> (SyncListener, UInt16) {
        let listener = SyncListener(
            rule: SyncAddressRule { [] },
            admit: { route, head, _ in
                route == .exchange && head.value("x-kelpie-sync-session") != "live" ? .reject(.error(401, "SYNC_SESSION")) : .accept
            },
            handle: { _, _, body, _ in .json(200, ["bytes": body.count]) }
        )
        let ready = AsyncStream<UInt16?> { continuation in
            listener.start(service: nil) { continuation.yield($0) }
        }
        for await port in ready {
            if let port { return (listener, port) }
        }
        throw XCTSkip("listener did not start")
    }

    private func request(_ path: String, length: Int, extra: [String] = [], body: String = "") -> Data {
        let lines = ["POST \(path) HTTP/1.1", "Content-Type: application/json", "Content-Length: \(length)"] + extra
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n" + body).utf8)
    }

    func testOversizedBodiesAndMissingSessionsAreRefusedBeforeTheBodyArrives() async throws {
        let (listener, port) = try await startListener()
        defer { listener.stop() }

        let ok = await rawRequest(port: port, request("/v1/sync/hello", length: 2, body: "{}"))
        XCTAssertEqual(ok.status, 200)

        // Only the head is sent; a listener that waited for the body would time out instead.
        let oversized = await rawRequest(port: port, request("/v1/sync/hello", length: 17_000))
        XCTAssertEqual(oversized.status, 413)
        XCTAssertLessThan(oversized.seconds, 2)

        let unauthenticated = await rawRequest(port: port, request("/v1/sync/exchange", length: 1_000_000))
        XCTAssertEqual(unauthenticated.status, 401)
        XCTAssertLessThan(unauthenticated.seconds, 2)

        let origin = await rawRequest(port: port, request("/v1/sync/hello", length: 2, extra: ["Origin: https://evil.example"], body: "{}"))
        XCTAssertEqual(origin.status, 403)

        let stalled = await rawRequest(port: port, request("/v1/sync/hello", length: 100, body: "{"))
        XCTAssertEqual(stalled.status, 408, "an incomplete body hits the 5 s read deadline")
    }

    // MARK: - Handshake admission on a real service

    @MainActor
    func testAuthIsSingleUseAndAForeignHintIsRefusedBeforeUOA() async throws {
        let directory = temporaryDirectory()
        let device = SyncTestDevice("responder", subject: "alice", directory: directory)
        device.boot()
        defer { device.shutDown() }
        await eventually("listener") { device.service?.listenerPort != nil }
        let port = try XCTUnwrap(device.service?.listenerPort)
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: try XCTUnwrap(NWEndpoint.Port(rawValue: port)))
        let responder = try XCTUnwrap(device.service?.run?.replica)
        let now = Int64(Date().timeIntervalSince1970 * 1_000)

        var sent: [String: String] = [:]
        func hello(subject: String, skew: Int64 = 0) async throws -> SyncHTTPResponse {
            let hint = try SyncStoreBridge.accountHints(subject: subject, now: now).current
            sent = ["replica": SyncCrypto.randomText(16), "key": SyncCrypto.publicKeyText(SyncCrypto.makePrivateKey()), "nonce": SyncCrypto.randomText(32)]
            let body: [String: Any] = [
                "v": 1, "replica": sent["replica"] ?? "", "hint": hint, "now": now + skew, "platform": "macos",
                "name": "Peer", "key": sent["key"] ?? "", "nonce": sent["nonce"] ?? ""
            ]
            return try await SyncHTTPClient.post(endpoint, path: "/v1/sync/hello", body: SyncJSON.data(body), timeout: 5, rule: SyncAddressRule { [] })
        }
        func post(_ path: String, _ body: [String: Any]) async throws -> SyncHTTPResponse {
            try await SyncHTTPClient.post(endpoint, path: path, body: SyncJSON.data(body), timeout: 5, rule: SyncAddressRule { [] })
        }

        let foreign = try await hello(subject: "bob")
        XCTAssertEqual(foreign.status, 409)
        XCTAssertEqual(SyncJSON.object(foreign.body)?["error"] as? String, "ACCOUNT_MISMATCH")
        let skewed = try await hello(subject: "alice", skew: 180_000)
        XCTAssertEqual(SyncJSON.object(skewed.body)?["error"] as? String, "CLOCK_SKEW")
        XCTAssertEqual(device.account.validated, 0, "refusals happen before any UOA call")

        let accepted = try await hello(subject: "alice")
        XCTAssertEqual(accepted.status, 200)
        let reply = try XCTUnwrap(SyncJSON.object(accepted.body))
        XCTAssertNil(SyncStoreBridge.invalidReason("hello-reply", reply))
        XCTAssertEqual(reply["replica"] as? String, responder)
        let handshakeId = try XCTUnwrap(reply["handshakeId"] as? String)

        let forged: [String: Any] = ["handshakeId": handshakeId, "ticket": "t.forged"]
        let first = try await post("/v1/sync/auth", forged)
        XCTAssertEqual(first.status, 403, "a ticket that does not validate is refused")
        let replay = try await post("/v1/sync/auth", forged)
        XCTAssertEqual(replay.status, 401, "the first auth consumed the handshake")
        XCTAssertEqual(SyncJSON.object(replay.body)?["error"] as? String, "SYNC_SESSION")
        XCTAssertTrue(device.service?.run?.channels.isEmpty ?? false)

        // A valid proof installs one session; replaying the same auth gets nothing.
        let secondHello = try await hello(subject: "alice")
        let second = try XCTUnwrap(SyncJSON.object(secondHello.body))
        let challenge = try SyncStoreBridge.challenge(initiator: sent, responder: [
            "replica": responder, "key": try XCTUnwrap(second["key"] as? String), "nonce": try XCTUnwrap(second["nonce"] as? String)
        ])
        let proof: [String: Any] = [
            "handshakeId": try XCTUnwrap(second["handshakeId"] as? String),
            "ticket": FakeSyncAccount.ticket("alice", challenge, "kelpie-sync:i:\(sent["replica"] ?? "")")
        ]
        let valid = try await post("/v1/sync/auth", proof)
        XCTAssertEqual(valid.status, 200)
        let answer = try XCTUnwrap(SyncJSON.object(valid.body))
        XCTAssertNil(SyncStoreBridge.invalidReason("auth-reply", answer))
        XCTAssertEqual(answer["ticket"] as? String, FakeSyncAccount.ticket("alice", challenge, "kelpie-sync:r:\(responder)"))
        XCTAssertEqual(device.service?.run?.channels.count, 1)
        let replayed = try await post("/v1/sync/auth", proof)
        XCTAssertEqual(replayed.status, 401)
        XCTAssertEqual(device.service?.run?.channels.count, 1, "keys are installed exactly once")
    }
}
