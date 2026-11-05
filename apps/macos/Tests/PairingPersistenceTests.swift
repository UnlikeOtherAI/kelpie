import XCTest
@testable import Kelpie

/// Computer permissions survive app restarts and later approvals without client tokens.
final class PairingPersistenceTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kelpie-pairing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("pairings.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }

    private func approveAlways(_ store: PairingStore, clientId: String, source: String) throws -> String {
        guard case .created(let request) = store.startPairing(
            clientId: clientId, clientName: clientId, sourceAddress: source
        ) else { throw XCTSkip("pair request was suppressed") }
        return try XCTUnwrap(store.approve(requestId: request.requestId, persist: true)?.token)
    }

    func testAlwaysAllowSurvivesRestartAndLaterApprovals() throws {
        let first = PairingStore(storeURL: storeURL)
        _ = try approveAlways(first, clientId: "minis", source: "192.168.1.215")
        // A second computer must preserve the first computer's permission.
        _ = try approveAlways(first, clientId: "umac", source: "192.168.1.192")

        let restarted = PairingStore(storeURL: storeURL)
        XCTAssertEqual(restarted.trustedComputers.clientId(for: "192.168.1.215"), "host:192.168.1.215")
        XCTAssertEqual(restarted.trustedComputers.clientId(for: "192.168.1.192"), "host:192.168.1.192")
        XCTAssertEqual(restarted.trustedComputers.list().count, 2)
        let trustURL = storeURL.deletingLastPathComponent().appendingPathComponent("trusted-computers.json")
        let mode = try FileManager.default.attributesOfItem(atPath: trustURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }
}
