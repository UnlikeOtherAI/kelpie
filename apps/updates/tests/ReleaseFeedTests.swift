import XCTest

final class ReleaseFeedTests: XCTestCase {
    private func entry(_ version: String, target: String = "macos-arm64", draft: Bool = false) -> [String: Any] {
        let url = target == "ios" ? "https://apps.apple.com/app/id123456789" :
            "https://github.com/UnlikeOtherAI/kelpie/releases/download/release/2026-11-09/Kelpie.zip"
        let item: [String: String] = ["target": target, "version": version, "url": url,
                                      "sha256": String(repeating: "a", count: 64)]
        let encoded = (try? JSONSerialization.data(withJSONObject: item)) ?? Data()
        return ["draft": draft, "prerelease": false,
                "body": "<!-- kelpie-update: \(String(decoding: encoded, as: UTF8.self)) -->"]
    }

    func testComponentVersionsAndNumericComparison() throws {
        let data = try JSONSerialization.data(withJSONObject: [entry("0.2.9"), entry("0.2.10"), entry("0.2.2")])
        XCTAssertEqual(AppRelease.newest(in: data, target: "macos-arm64", installed: "0.2.0")?.version, "0.2.10")
        XCTAssertNil(AppRelease.newest(in: data, target: "macos-x64", installed: "0.2.0"))
        XCTAssertNil(AppRelease.newest(in: data, target: "macos-arm64", installed: "0.2.10"))
        XCTAssertNil(AppRelease.newest(in: data, target: "macos-arm64", installed: "0.3.0"))
    }

    func testDraftMalformedAndUnrelatedReleases() throws {
        let data = try JSONSerialization.data(withJSONObject: [entry("9.0.0", draft: true),
            entry("9.0.0", target: "ios"), ["body": "<!-- kelpie-update: {broken} -->"], entry("0.2.1")])
        XCTAssertEqual(AppRelease.newest(in: data, target: "macos-arm64", installed: "0.2.0")?.version, "0.2.1")
        XCTAssertNil(AppRelease.newest(in: Data("{broken}".utf8), target: "macos-arm64", installed: "0.2.0"))
    }

    func testMobileNeedsARealStoreRoute() throws {
        let data = try JSONSerialization.data(withJSONObject: [entry("0.2.1", target: "ios")])
        XCTAssertEqual(AppRelease.newest(in: data, target: "ios", installed: "0.2.0")?.version, "0.2.1")
        let simulator = try XCTUnwrap(URL(string: "https://github.com/UnlikeOtherAI/kelpie/releases/download/tag/Kelpie-simulator.zip"))
        XCTAssertFalse(AppRelease.allowedURL(simulator, target: "ios"))
        let unsafe = try XCTUnwrap(URL(string: "https://github.com.evil.example/update.zip"))
        XCTAssertFalse(AppRelease.allowedURL(unsafe, target: "macos-arm64"))
    }

    @MainActor
    func testSkipAndNotNowStorage() throws {
        let suite = "KelpieUpdateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = AppRelease(target: "ios", version: "0.2.1",
                              url: try XCTUnwrap(URL(string: "https://apps.apple.com/app/id123456789")), sha256: nil)
        let updates = AppUpdates(defaults: defaults, installed: "0.2.0", target: "ios")
        updates.offered = item
        updates.notNow()
        XCTAssertNil(updates.offered)
        XCTAssertNil(defaults.stringArray(forKey: "updates.skippedVersions"))
        updates.skip(item)
        XCTAssertEqual(defaults.stringArray(forKey: "updates.skippedVersions"), ["0.2.1"])
        let restarted = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(restarted.stringArray(forKey: "updates.skippedVersions"), ["0.2.1"])
    }
}
