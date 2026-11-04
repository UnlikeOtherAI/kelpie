import XCTest
import UIKit

final class FavouritesUITests: XCTestCase {
    @MainActor
    func testNestedMoveRemoveAndUndo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hideWelcomeCard", "YES"]
        app.launch()
        if UIDevice.current.userInterfaceIdiom == .pad {
            let bookmarks = app.buttons["browser.bookmarks"]
            XCTAssertTrue(bookmarks.waitForExistence(timeout: 20))
            bookmarks.tap()
        } else {
            let more = app.descendants(matching: .any)["browser.more"].firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 20))
            more.tap()
            let bookmarks = app.descendants(matching: .any)["Bookmarks"].firstMatch
            XCTAssertTrue(bookmarks.waitForExistence(timeout: 5))
            bookmarks.tap()
        }
        let addButton = app.descendants(matching: .any)["browser.bookmarks.add"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        app.buttons["New Folder"].tap()
        let name = app.textFields["browser.bookmarks.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (name.value as? String)?.count ?? 20))
        let title = "Drag fixture " + UUID().uuidString.prefix(8)
        name.typeText(title)
        app.buttons["browser.bookmarks.save"].tap()
        let folderRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "browser.bookmarks.row.", title)).firstMatch
        XCTAssertTrue(folderRow.waitForExistence(timeout: 5), app.debugDescription)
        let id = String(folderRow.identifier.dropFirst("browser.bookmarks.row.".count))
        let actions = app.descendants(matching: .any)["browser.bookmarks.actions.\(id)"].firstMatch
        actions.tap()
        let addPage = app.descendants(matching: .any)["Add Current Page Here"].firstMatch
        XCTAssertTrue(addPage.waitForExistence(timeout: 5))
        addPage.tap()
        let visibleBefore = Set(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.bookmarks.row.")).allElementsBoundByIndex.map(\.identifier))
        folderRow.tap()
        let added = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.bookmarks.row.")).allElementsBoundByIndex.first { !visibleBefore.contains($0.identifier) }
        XCTAssertNotNil(added)
        let pageRow = app.buttons[added!.identifier]
        XCTAssertTrue(pageRow.waitForExistence(timeout: 5))
        let pageId = String(pageRow.identifier.dropFirst("browser.bookmarks.row.".count))
        let handle = app.images["browser.bookmarks.drag.\(pageId)"]
        handle.press(forDuration: 0.8, thenDragTo: app.staticTexts["browser.bookmarks.root"])
        folderRow.tap()
        XCTAssertTrue(pageRow.exists)
        handle.press(forDuration: 0.8, thenDragTo: folderRow)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: pageRow)
        waitForExpectations(timeout: 5)
        folderRow.tap()
        XCTAssertTrue(pageRow.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = UIDevice.current.userInterfaceIdiom == .pad ? "tablet-favourites-tree" : "phone-favourites-tree"
        shot.lifetime = .keepAlways
        add(shot)
        actions.tap()
        app.buttons["Remove"].tap()
        XCTAssertTrue(app.staticTexts["Remove this favourite?"].waitForExistence(timeout: 5))
        app.buttons["Remove"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: folderRow)
        waitForExpectations(timeout: 5)
        app.buttons["browser.bookmarks.undo"].tap()
        XCTAssertTrue(folderRow.waitForExistence(timeout: 5))
        XCTAssertTrue(pageRow.waitForExistence(timeout: 5))
    }
}
