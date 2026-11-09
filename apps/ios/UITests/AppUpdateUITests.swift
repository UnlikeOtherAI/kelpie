import XCTest

final class AppUpdateUITests: XCTestCase {
    private func launch(version: String) throws -> XCUIApplication {
        let item = ["target": "ios", "version": version, "url": "https://apps.apple.com/app/id123456789"]
        let metadata = try JSONSerialization.data(withJSONObject: item)
        let release: [[String: Any]] = [["draft": false, "prerelease": false,
            "body": "<!-- kelpie-update: \(String(decoding: metadata, as: UTF8.self)) -->"]]
        let app = XCUIApplication()
        app.launchEnvironment["KELPIE_UPDATE_TEST_FEED_JSON"] = String(
            decoding: try JSONSerialization.data(withJSONObject: release), as: UTF8.self)
        app.launch()
        return app
    }

    func testNotNowAsksOnRestartAndSkipOnlyHidesThatVersion() throws {
        // A unique version leaves the real app's existing preferences untouched.
        let suffix = Int(Date().timeIntervalSince1970) % 900_000
        let version = "999.\(suffix).0"
        var app = try launch(version: version)
        let prompt = app.alerts["A new Kelpie version is available"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 15))
        XCTAssertTrue(prompt.buttons["Update"].exists)
        XCTAssertTrue(prompt.buttons["Skip version"].exists)
        prompt.buttons["Not now"].tap()
        XCTAssertFalse(prompt.exists)
        app.terminate()

        app = try launch(version: version)
        let repeated = app.alerts["A new Kelpie version is available"]
        XCTAssertTrue(repeated.waitForExistence(timeout: 15))
        repeated.buttons["Skip version"].tap()
        app.terminate()

        app = try launch(version: version)
        XCTAssertFalse(app.alerts["A new Kelpie version is available"].waitForExistence(timeout: 3))
        app.terminate()

        app = try launch(version: "999.\(suffix).1")
        XCTAssertTrue(app.alerts["A new Kelpie version is available"].waitForExistence(timeout: 15))
        app.alerts["A new Kelpie version is available"].buttons["Not now"].tap()
    }
}
