import XCTest
@testable import Kelpie

/// "Always allow" must survive an app restart and later approvals: the next
/// store instance reads the same file and still accepts the issued bearer.
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
        let mini = try approveAlways(first, clientId: "minis", source: "192.168.1.215")
        // A second approval replaces the existing file rather than appending.
        let umac = try approveAlways(first, clientId: "umac", source: "192.168.1.192")

        let restarted = PairingStore(storeURL: storeURL)
        XCTAssertEqual(restarted.validateBearer(mini), "minis")
        XCTAssertEqual(restarted.validateBearer(umac), "umac")
        XCTAssertEqual(restarted.listPersistent().count, 2)
        let mode = try FileManager.default.attributesOfItem(atPath: storeURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }
}
