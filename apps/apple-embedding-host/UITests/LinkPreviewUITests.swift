import XCTest
#if os(macOS)
import AppKit

final class LinkPreviewUITests: XCTestCase {
    @MainActor
    func testHoverPreviewDoesNotReserveSpaceOrInterceptLinks() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.kelpie.browser.macos")
        app.activate()
        app.typeKey("t", modifierFlags: .command)
        defer { app.typeKey("w", modifierFlags: .command) }
        let address = app.textFields["browser.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 15))
        address.click()
        app.typeKey("a", modifierFlags: .command)
        let html = """
        <meta charset="utf-8"><title>Link preview</title>
        <style>html{background:#f7f9fc;color:#26334d;font:18px -apple-system}body{margin:40px;height:1600px}
        a{display:block;width:max-content;margin:24px 0;color:#1767b7}#bottom{position:fixed;bottom:8px;left:10px;margin:0}</style>
        <h1>Link preview</h1><p>Hover over a link to see its destination.</p>
        <p>Move onto this text to hide the preview.</p>
        <a href="https://example.org/">Short destination</a>
        <a href="https://example.org/another-page">Another destination</a>
        <a href="https://example.org/\(String(repeating: "segment/", count: 60))">Long destination</a>
        <a id="bottom" href="https://example.org/click-through" onclick="event.preventDefault();this.textContent='Bottom link clicked'">Link underneath the preview</a>
        """
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []
        defer { pasteboard.clearContents(); pasteboard.writeObjects(previous) }
        pasteboard.clearContents()
        pasteboard.setString("data:text/html;base64," + Data(html.utf8).base64EncodedString(), forType: .string)
        app.typeKey("v", modifierFlags: .command)
        app.typeKey(.return, modifierFlags: [])
        let short = app.webViews.links["Short destination"]
        XCTAssertTrue(short.waitForExistence(timeout: 15))
        let preview = app.staticTexts["browser.status.link"]
        let viewport = app.webViews.firstMatch.frame
        short.hover()
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        capture("short", app: app)
        XCTAssertLessThan(preview.frame.width, app.windows.firstMatch.frame.width / 2)
        XCTAssertEqual(app.webViews.firstMatch.frame, viewport)
        app.webViews.links["Another destination"].hover()
        waitForValue("https://example.org/another-page", in: preview)
        app.webViews.links["Long destination"].hover()
        waitForValue("https://example.org/" + String(repeating: "segment/", count: 60), in: preview)
        capture("long", app: app)
        XCTAssertLessThanOrEqual(preview.frame.width, 640)
        app.webViews.firstMatch.scroll(byDeltaX: 0, deltaY: 200)
        waitForHidden(preview)
        let bottom = app.webViews.links["Link underneath the preview"]
        bottom.hover()
        bottom.click()
        XCTAssertTrue(app.webViews.links["Bottom link clicked"].waitForExistence(timeout: 5))
        address.hover()
        waitForHidden(preview)
        capture("idle", app: app)
    }

    @MainActor
    private func waitForValue(_ value: String, in element: XCUIElement) {
        let updated = expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        wait(for: [updated], timeout: 5)
    }

    @MainActor
    private func waitForHidden(_ element: XCUIElement) {
        let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        wait(for: [hidden], timeout: 5)
    }

    @MainActor
    private func capture(_ state: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "link-preview-" + state
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
