import XCTest

#if os(macOS)
import AppKit

/// Run against an isolated copy of the standalone app. Other native verification
/// jobs can otherwise relaunch the same bundle identifier during this journey.
final class DesktopAddressUITests: XCTestCase {
    @MainActor
    func testNewTabAndInitialAddressSelection() throws {
        continueAfterFailure = false
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let app = XCUIApplication(url: repository.appendingPathComponent(
            ".cache/address-ui/KelpieAddressVerification.app"
        ))
        app.activate()
        let address = app.textFields["browser.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 15))
        app.typeKey("t", modifierFlags: .command)
        capture("macos-newtab", app)
        app.typeText("address-focus-check")
        let typedAfterNewTab = address.value as? String
        address.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        app.typeKey("a", modifierFlags: .command)
        let html = "<title>Address editing test</title><input aria-label='Page focus'>"
        let url = "data:text/html;base64," + Data(html.utf8).base64EncodedString()
        pasteFixture(url, into: address, app: app)
        app.typeKey(.return, modifierFlags: [])
        let pageInput = app.webViews.textFields["Page focus"]
        XCTAssertTrue(pageInput.waitForExistence(timeout: 15))
        pageInput.click()
        address.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        capture("macos-address-selected", app)
        app.typeText("replacement")
        XCTAssertEqual(address.value as? String, "replacement")
        app.typeKey(.leftArrow, modifierFlags: [])
        app.typeText("x")
        XCTAssertEqual(address.value as? String, "replacemenxt")
        XCTAssertEqual(typedAfterNewTab, "address-focus-check")
    }

    @MainActor
    private func pasteFixture(_ text: String, into address: XCUIElement, app: XCUIApplication) {
        let pasteboard = NSPasteboard.general
        let previous = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let fixtureChange = pasteboard.changeCount
        defer {
            if pasteboard.changeCount == fixtureChange {
                pasteboard.clearContents()
                pasteboard.writeObjects(previous)
            }
        }
        app.typeKey("v", modifierFlags: .command)
        let pasted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            address.value as? String == text
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pasted], timeout: 5), .completed, "Fixture paste did not finish")
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
