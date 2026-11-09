import XCTest
@testable import KelpieBrowser

/// Two or more `CookieSyncService`s over real loopback HTTP with real crypto, in-memory
/// cookie engines and a deterministic fake UOA.
@MainActor
final class CookieSyncIntegrationTests: XCTestCase {
    private var directory: URL!
    private var devices: [SyncTestDevice] = []

    override func setUp() async throws {
        directory = temporaryDirectory()
    }

    override func tearDown() async throws {
        devices.forEach { $0.shutDown() }
        devices = []
        try? FileManager.default.removeItem(at: directory)
    }

    private func device(_ name: String, subject: String?, timing: SyncTiming = .fast) -> SyncTestDevice {
        let created = SyncTestDevice(name, subject: subject, directory: directory)
        created.timing = timing
        devices.append(created)
        created.boot()
        return created
    }

    /// Waits for every signed-in device to listen, then shows each the others' adverts.
    private func publish() async {
        await eventually("listeners") { devices.allSatisfy { $0.account.subject == nil || $0.advert != nil } }
        for device in devices {
            device.discovery?.publish(devices.filter { $0 !== device }.compactMap(\.advert))
        }
    }

    private func connected(_ lhs: SyncTestDevice, _ rhs: SyncTestDevice) -> Bool {
        guard let left = lhs.service?.run, let right = rhs.service?.run else { return false }
        return left.channel(for: right.replica) != nil && right.channel(for: left.replica) != nil
    }

    private func warmedUp(_ device: SyncTestDevice) async -> Bool {
        let store = await device.status()["store"] as? [String: Any]
        return store?["warming"] as? Bool == false
    }

    private func pair(_ lhs: SyncTestDevice, _ rhs: SyncTestDevice) async {
        await publish()
        await eventually("session") { connected(lhs, rhs) }
        for device in [lhs, rhs] { await eventually("warm-up on \(device.name)") { await warmedUp(device) } }
    }

    func testLoginAndLogoutPropagateBothWays() async throws {
        let mac = device("mac", subject: "alice")
        let phone = device("phone", subject: "alice")
        await pair(mac, phone)

        mac.source.set(".example.com", "sid", "login-1")
        mac.source.set("example.com", "session", "s-1", expires: nil)
        await eventually("login reaches the phone") {
            phone.source.value(".example.com", "sid") == "login-1" && phone.source.value("example.com", "session") == "s-1"
        }

        phone.source.set(".example.com", "sid", "login-2")
        await eventually("an edit on the phone reaches the mac") { mac.source.value(".example.com", "sid") == "login-2" }

        phone.source.remove(".example.com", "sid")
        await eventually("logout reaches the mac") { mac.source.value(".example.com", "sid") == nil }
        XCTAssertEqual(mac.source.value("example.com", "session"), "s-1", "only the logged-out cookie goes")

        let status = await mac.status()
        XCTAssertEqual(status["signedIn"] as? Bool, true)
        let peers = try XCTUnwrap(status["peers"] as? [[String: Any]])
        XCTAssertEqual(peers.first?["state"] as? String, "connected")
        XCTAssertEqual(peers.first?["platform"] as? String, "ios")
        XCTAssertNotNil(peers.first?["lastSyncAt"])
        XCTAssertGreaterThanOrEqual(mac.account.validated, 1)
    }

    func testRestartRestoresSessionCookiesWithoutLoggingPeersOut() async throws {
        let mac = device("mac", subject: "alice")
        let phone = device("phone", subject: "alice")
        await pair(mac, phone)
        mac.source.set("example.com", "session", "s-1", expires: nil)
        mac.source.set(".example.com", "persistent", "p-1")
        await eventually("initial sync") { phone.source.value("example.com", "session") == "s-1" }
        let oldReplica = phone.service?.run?.replica

        phone.restart()
        XCTAssertNil(phone.source.value("example.com", "session"), "the restart lost the session cookie")
        await pair(mac, phone)
        XCTAssertNotEqual(phone.service?.run?.replica, oldReplica, "every open uses a fresh replica id")
        await eventually("the session cookie comes back") { phone.source.value("example.com", "session") == "s-1" }

        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(mac.source.value("example.com", "session"), "s-1", "a restart is not a logout")
        XCTAssertEqual(mac.source.value(".example.com", "persistent"), "p-1")
    }

    func testAnotherAccountNeverReceivesCookies() async throws {
        let mac = device("mac", subject: "alice")
        let stranger = device("stranger", subject: "bob")
        // Knows alice's subject, so its hint matches, but UOA only issues it tickets for itself.
        let impostor = device("impostor", subject: "alice")
        impostor.account.ticketSubject = "mallory"
        mac.source.set(".example.com", "sid", "secret")
        await publish()

        await eventually("the impostor's proof is refused") {
            mac.service?.run?.peers[impostor.service?.run?.replica ?? ""]?.lastError == "PROOF_REJECTED"
                || impostor.service?.run?.peers[mac.service?.run?.replica ?? ""]?.lastError == "PROOF_REJECTED"
        }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertNil(stranger.source.value(".example.com", "sid"))
        XCTAssertNil(impostor.source.value(".example.com", "sid"))
        XCTAssertNil(mac.service?.run?.peers[stranger.service?.run?.replica ?? ""], "a foreign hint is never even considered")
        XCTAssertFalse(connected(mac, impostor))
    }

    func testSignOutAndAccountChangeStopSyncing() async throws {
        let mac = device("mac", subject: "alice")
        let phone = device("phone", subject: "alice")
        await pair(mac, phone)
        mac.source.set(".example.com", "sid", "alice-1")
        await eventually("first sync") { phone.source.value(".example.com", "sid") == "alice-1" }

        phone.account.signOut()
        await eventually("sign-out closes the run") { phone.service?.run == nil }
        let signedOut = await phone.status()
        XCTAssertEqual(signedOut["signedIn"] as? Bool, false)
        XCTAssertEqual(signedOut["listening"] as? Bool, false)

        phone.account.signIn("bob")
        await eventually("bob's run opens") { phone.service?.run?.fence.subject == "bob" }
        await publish()
        mac.source.set(".example.com", "sid", "alice-2")
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(phone.source.value(".example.com", "sid"), "alice-1", "alice's later changes never reach bob")
        XCTAssertFalse(connected(mac, phone))
        let store = await phone.status()["store"] as? [String: Any]
        XCTAssertEqual(store?["localOnly"] as? Int, 1, "alice's cookie stays local under bob")
    }

    func testExpiredSessionsHandshakeAgainAndKeepSyncing() async throws {
        var short = SyncTiming.fast
        short.sessionMillis = 1_500
        let mac = device("mac", subject: "alice", timing: short)
        let phone = device("phone", subject: "alice", timing: short)
        await pair(mac, phone)
        let first = try XCTUnwrap(mac.service?.run?.channel(for: phone.service?.run?.replica ?? "")?.sessionId)
        await eventually("a new session after expiry") {
            guard let current = mac.service?.run?.channel(for: phone.service?.run?.replica ?? "")?.sessionId else { return false }
            return current != first && connected(mac, phone)
        }
        mac.source.set(".example.com", "sid", "after-expiry")
        await eventually("sync continues on the new session") { phone.source.value(".example.com", "sid") == "after-expiry" }
        XCTAssertGreaterThanOrEqual(mac.account.issued, 2, "every session needs fresh UOA proofs")
    }

    func testBackgroundStopsSyncAndForegroundRestartsWithANewReplica() async throws {
        let mac = device("mac", subject: "alice")
        let phone = device("phone", subject: "alice")
        await pair(mac, phone)
        let background = try XCTUnwrap(phone.service?.run?.replica)

        phone.source.set(".example.com", "late", "flushed")
        await phone.service?.flush(timeout: 5)
        phone.service?.setActive(false)
        XCTAssertNil(phone.service?.run, "backgrounding stops the listener and browsing")
        await eventually("the flush reached the mac") { mac.source.value(".example.com", "late") == "flushed" }

        mac.source.set(".example.com", "sid", "while-away")
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(phone.source.value(".example.com", "sid"), "nothing syncs while suspended")

        phone.service?.setActive(true)
        await eventually("foreground opens a new run") { phone.service?.run != nil }
        XCTAssertNotEqual(phone.service?.run?.replica, background)
        XCTAssertEqual(phone.service?.run?.warming, false, "a foreground restart is launch:false")
        await publish()
        await eventually("changes made while away arrive") { phone.source.value(".example.com", "sid") == "while-away" }
    }
}
