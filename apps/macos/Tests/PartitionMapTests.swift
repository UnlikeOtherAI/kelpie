import XCTest
@testable import Kelpie

/// Covers the corruption and reconciliation policy the plan specifies. These
/// are the parts of the partition registry that can be tested without a live
/// WebKit environment; the engine-facing half lives in `PartitionRegistry`.
final class PartitionMapTests: XCTestCase {
    /// Two distinct store ids. Only their distinctness matters, never their
    /// value, so freshly minted ones keep the fixtures free of optionals.
    private let uuidA = UUID()
    private let uuidB = UUID()

    // MARK: - Decode

    func testDecodesWellFormedEntries() {
        let (map, warnings) = PartitionMap.decode([
            "sam": uuidA.uuidString,
            "morgan": uuidB.uuidString
        ])

        XCTAssertEqual(map.identifier(for: "sam"), uuidA)
        XCTAssertEqual(map.identifier(for: "morgan"), uuidB)
        XCTAssertTrue(warnings.isEmpty)
    }

    func testDropsUnparseableIdentifiers() {
        let (map, warnings) = PartitionMap.decode(["sam": uuidA.uuidString, "morgan": "not-a-uuid"])

        XCTAssertEqual(map.identifier(for: "sam"), uuidA)
        XCTAssertNil(map.identifier(for: "morgan"))
        XCTAssertEqual(warnings.count, 1)
    }

    func testDropsDuplicateIdentifiersDeterministically() {
        // Two partitions claiming one store. The survivor must not depend on
        // dictionary ordering, or the app would alternate between them across
        // launches — worse than either choice.
        for _ in 0..<5 {
            let (map, warnings) = PartitionMap.decode([
                "zoe": uuidA.uuidString,
                "alice": uuidA.uuidString
            ])
            XCTAssertEqual(map.identifier(for: "alice"), uuidA)
            XCTAssertNil(map.identifier(for: "zoe"))
            XCTAssertEqual(warnings.count, 1)
        }
    }

    func testDecodeOfAnEmptyMapYieldsNoWarnings() {
        let (map, warnings) = PartitionMap.decode([:])
        XCTAssertTrue(map.encoded().isEmpty)
        XCTAssertTrue(warnings.isEmpty)
    }

    func testEncodeRoundTrips() {
        let raw = ["sam": uuidA.uuidString]
        XCTAssertEqual(PartitionMap.decode(raw).map.encoded(), raw)
    }

    // MARK: - Minting

    func testMakeIdentifierIsStableForTheSameId() {
        var map = PartitionMap()
        let first = map.makeIdentifier(for: "sam")
        XCTAssertEqual(map.makeIdentifier(for: "sam"), first)
        XCTAssertNotEqual(map.makeIdentifier(for: "morgan"), first)
    }

    func testRemoveForgetsTheIdentifier() {
        var map = PartitionMap()
        _ = map.makeIdentifier(for: "sam")
        map.remove("sam")
        XCTAssertNil(map.identifier(for: "sam"))
    }

    // MARK: - Reconciliation

    func testDanglingIdsReportsEntriesWithNoEngineStore() {
        var map = PartitionMap()
        let sam = map.makeIdentifier(for: "sam")
        _ = map.makeIdentifier(for: "morgan")

        XCTAssertEqual(map.danglingIds(engineIdentifiers: [sam], liveIds: []), ["morgan"])
    }

    func testDanglingIdsSparesPartitionsThatStillHaveTabs() {
        var map = PartitionMap()
        _ = map.makeIdentifier(for: "sam")
        // A store only appears in the engine once a web view writes to it, so a
        // freshly created partition with an open tab is legitimately absent.
        // Dropping it would fork the identity behind a familiar name.
        XCTAssertTrue(map.danglingIds(engineIdentifiers: [], liveIds: ["sam"]).isEmpty)
    }

    func testOrphansReportsEngineStoresTheMapDoesNotKnow() {
        var map = PartitionMap()
        let sam = map.makeIdentifier(for: "sam")

        XCTAssertTrue(map.orphans(engineIdentifiers: [sam]).isEmpty)
        XCTAssertEqual(Set(map.orphans(engineIdentifiers: [sam, uuidA, uuidB])), Set([uuidA, uuidB]))
    }

    // MARK: - Orphan ids

    func testOrphanIdRoundTrips() {
        let id = PartitionMap.orphanId(for: uuidA)
        XCTAssertTrue(id.hasPrefix(PartitionMap.orphanPrefix))
        XCTAssertEqual(PartitionMap.orphanIdentifier(from: id), uuidA)
    }

    func testOrphanIdentifierRejectsOrdinaryPartitionIds() {
        XCTAssertNil(PartitionMap.orphanIdentifier(from: "sam.eng-lead"))
        XCTAssertNil(PartitionMap.orphanIdentifier(from: "orphan:not-a-uuid"))
    }

    func testOrphanIdsAreRejectedByTheUserFacingValidator() {
        // They contain a colon, so a caller cannot create a tab that collides
        // with a synthesised orphan id. delete-partition allows them
        // explicitly.
        XCTAssertNotNil(PartitionValidator.validate(PartitionMap.orphanId(for: uuidA)))
    }
}
