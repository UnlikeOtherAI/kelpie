import XCTest
@testable import Kelpie

final class NetworkTrafficStoreTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "kelpie-network-tests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func persistence() -> NetworkTrafficPersistence {
        NetworkTrafficPersistence(fileURL: directory.appendingPathComponent("traffic.json"), defaults: defaults, interval: 3600)
    }

    private func entry(_ index: Int, method: String = "get", body: String? = nil) -> NetworkTrafficStore.TrafficEntry {
        .init(
            id: UUID(),
            method: method,
            url: "https://fixture.test/\(index)",
            statusCode: 201,
            contentType: "application/json",
            requestHeaders: ["Accept": "application/json"],
            responseHeaders: [:],
            requestBody: nil,
            responseBody: body,
            startTime: Date(timeIntervalSince1970: 1_700_000_000.123),
            duration: -1,
            size: -1,
            initiator: "js"
        )
    }

    func testIncrementalCaptureMatchesCoreFilteringAndSelectionAfterEviction() {
        let store = NetworkTrafficStore(persistence: persistence())
        for index in 0..<2000 { store.append(entry(index)) }
        store.selectedIndex = 1
        let selectedID = store.selectedEntry?.id
        store.append(entry(2000, method: "post"))
        XCTAssertEqual(store.entries.count, 2000)
        XCTAssertEqual(store.entries.first?.url, "https://fixture.test/1")
        XCTAssertEqual(store.selectedIndex, 0)
        XCTAssertEqual(store.selectedEntry?.id, selectedID)
        let summary = store.toSummaryJSON()
        XCTAssertEqual(summary.map { $0["url"] as? String }, store.entries.map { Optional($0.url) })
        XCTAssertEqual(summary.map { $0["method"] as? String }, store.entries.map { Optional($0.method) })
        XCTAssertEqual(store.entries.last?.duration, 0)
        XCTAssertEqual(store.entries.last?.size, 0)
        XCTAssertEqual(store.toSummaryJSON(method: "post", category: "json", statusRange: "200-299").count, 1)
        store.append(entry(2001))
        XCTAssertNil(store.selectedEntry, "Evicting the selected request must clear the selection")
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.toSummaryJSON().isEmpty)
    }

    func testLargeLegacyHistoryMigratesWithoutBodyLossAndCaptureDoesNotRewriteIt() throws {
        let body = String(repeating: "fixture", count: 1500)
        let rows = (0..<2000).map { entry($0, body: body) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacy = try encoder.encode(rows)
        XCTAssertGreaterThan(legacy.count, 4 * 1024 * 1024)
        defaults.set(legacy, forKey: NetworkTrafficPersistence.legacyKey)
        let writer = persistence()
        let store = NetworkTrafficStore(persistence: writer)
        XCTAssertEqual(store.entries.count, rows.count)
        for index in 2000..<2100 { store.append(entry(index, body: body)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.fileURL.path), "Burst writes must be coalesced")
        XCTAssertNotNil(defaults.data(forKey: NetworkTrafficPersistence.legacyKey))
        store.flush()
        XCTAssertNil(defaults.object(forKey: NetworkTrafficPersistence.legacyKey))
        let restored = NetworkTrafficStore(persistence: persistence())
        XCTAssertEqual(restored.entries.map(\.id), store.entries.map(\.id))
        XCTAssertEqual(restored.entries.last?.responseBody, body)
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: writer.fileURL.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(mode.intValue, 0o600)
    }

    func testClearSupersedesPendingSnapshotsAndRemainsClearedAfterRestart() throws {
        let writer = persistence()
        let store = NetworkTrafficStore(persistence: writer)
        store.append(entry(1, body: "before"))
        store.flush()
        store.append(entry(2, body: "pending"))
        store.clear()
        XCTAssertTrue(NetworkTrafficStore(persistence: persistence()).entries.isEmpty)
        store.append(entry(3, body: "after"))
        store.flush()
        let restored = NetworkTrafficStore(persistence: persistence())
        XCTAssertEqual(restored.entries.map(\.url), ["https://fixture.test/3"])
    }

    func testFailedMigrationRetainsLegacyAndRetriesLatestSnapshot() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blocker)
        let writer = NetworkTrafficPersistence(fileURL: blocker.appendingPathComponent("traffic.json"), defaults: defaults, interval: 3600)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode([entry(1)]), forKey: NetworkTrafficPersistence.legacyKey)
        let store = NetworkTrafficStore(persistence: writer)
        store.flush()
        XCTAssertNotNil(defaults.object(forKey: NetworkTrafficPersistence.legacyKey))
        store.append(entry(2))
        try FileManager.default.removeItem(at: blocker)
        store.flush()
        XCTAssertNil(defaults.object(forKey: NetworkTrafficPersistence.legacyKey))
        XCTAssertEqual(NetworkTrafficStore(persistence: writer).entries.count, 2)
    }

    func testUnreadableHistoryIsPreservedBeforeAnyNewCapture() throws {
        let writer = persistence()
        try FileManager.default.createDirectory(at: writer.fileURL, withIntermediateDirectories: true)
        let original = writer.fileURL.appendingPathComponent("original")
        try Data("retained".utf8).write(to: original)
        let store = NetworkTrafficStore(persistence: writer)
        store.append(entry(1))
        store.flush()
        let recovery = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("traffic.json.unreadable-") })
        XCTAssertEqual(try Data(contentsOf: recovery.appendingPathComponent("original")), Data("retained".utf8))
        XCTAssertEqual(NetworkTrafficStore(persistence: persistence()).entries.count, 1)
    }

    func testFailedClearRetriesEmptySnapshotWithoutResurrectingPendingTraffic() throws {
        let writer = persistence()
        let store = NetworkTrafficStore(persistence: writer)
        store.append(entry(1))
        store.flush()
        // Block the destination's rename while preserving the old test history.
        let saved = directory.appendingPathComponent("saved.json")
        try FileManager.default.moveItem(at: writer.fileURL, to: saved)
        try FileManager.default.createDirectory(at: writer.fileURL, withIntermediateDirectories: false)
        store.append(entry(2))
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        try FileManager.default.removeItem(at: writer.fileURL)
        try FileManager.default.moveItem(at: saved, to: writer.fileURL)
        store.flush()
        XCTAssertTrue(NetworkTrafficStore(persistence: persistence()).entries.isEmpty)
    }

    func testIncrementalEntryMatchesEveryCoreField() throws {
        let core = try XCTUnwrap(kelpie_network_traffic_store_create())
        defer { kelpie_network_traffic_store_destroy(core) }
        let store = NetworkTrafficStore(persistence: persistence())
        let input = entry(1, method: "gétß", body: "")
        let data = try JSONSerialization.data(withJSONObject: store.entryToJSON(input))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(json.withCString { kelpie_network_traffic_store_append_json(core, $0) }, 1)
        store.append(input)
        let raw = try XCTUnwrap(kelpie_network_traffic_store_to_json(core))
        defer { kelpie_free_string(raw) }
        // Load the actual core export through the legacy reader to compare the
        // same UI representation, including nil bodies and timestamp rounding.
        defaults.set(String(cString: raw), forKey: NetworkTrafficPersistence.legacyKey)
        let reference = NetworkTrafficStore(persistence: persistence())
        let actual = try XCTUnwrap(store.entries.first)
        let expected = try XCTUnwrap(reference.entries.first)
        XCTAssertEqual(store.entryToJSON(actual) as NSDictionary, reference.entryToJSON(expected) as NSDictionary)
    }

    func testDocumentNavigationPreservesStatusAndStringLegacyFormat() throws {
        defaults.set("[{\"method\":\"get\",\"url\":\"https://fixture.test/old\",\"startTime\":0}]", forKey: NetworkTrafficPersistence.legacyKey)
        let store = NetworkTrafficStore(persistence: persistence())
        store.appendDocumentNavigation(url: "https://fixture.test/document", statusCode: 404, contentType: "text/html", startedAt: Date())
        XCTAssertEqual(store.documentNavigationStatuses()["https://fixture.test/document"], 404)
        XCTAssertEqual(store.entries.first?.startTime, Date(timeIntervalSinceReferenceDate: 0))
        store.flush()
        XCTAssertEqual(NetworkTrafficStore(persistence: persistence()).entries.count, 2)
    }
}
