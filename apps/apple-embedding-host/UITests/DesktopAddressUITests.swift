import XCTest

#if os(macOS)
/// Run against an isolated copy of the standalone app. Other native verification
/// jobs can otherwise relaunch the same bundle identifier during this journey.
final class DesktopAddressUITests: XCTestCase {
    @MainActor
    func testNewTabAndInitialAddressSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.kelpie.browser.address-focus-verification")
        app.activate()
        let address = app.textFields["browser.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 15))
        app.typeKey("t", modifierFlags: .command)
        capture("macos-newtab", app)
        app.typeText("address-focus-check")
        let typedAfterNewTab = address.value as? String
        address.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("https://example.org/a-long-address")
        app.typeKey(.tab, modifierFlags: [])
        address.click()
        capture("macos-address-selected", app)
        app.typeText("replacement")
        XCTAssertEqual(address.value as? String, "replacement")
        app.typeKey(.leftArrow, modifierFlags: [])
        app.typeText("x")
        XCTAssertEqual(address.value as? String, "replacemenxt")
        XCTAssertEqual(typedAfterNewTab, "address-focus-check")
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
