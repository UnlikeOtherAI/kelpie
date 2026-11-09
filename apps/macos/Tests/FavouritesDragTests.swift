import AppKit
import XCTest
@testable import KelpieBrowser

/// Drives the favourites bar's own drag loop with real AppKit events: the press
/// goes to `FavouriteButton.mouseDown`, and the drags, release or Escape are
/// queued for the loop to read, exactly as the window server would deliver them.
@MainActor
final class FavouritesDragTests: XCTestCase {
    private var suite = ""
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.close()
        UserDefaults().removePersistentDomain(forName: suite)
        try await super.tearDown()
    }

    func testDroppingFarFromTheBarRemovesTheFavouriteWithAPuff() async throws {
        let (store, bar) = try makeBar(["One", "Two"])
        let start = try centre(of: button(bar, "Two"))
        try drag(button(bar, "Two"), from: start, through: [offset(start, 8, -8), offset(start, 20, -100), offset(start, 40, -160)])
        try await waitUntil { store.bookmarks.count == 1 }
        XCTAssertEqual(store.bookmarks.map(\.title), ["One"])
        XCTAssertTrue(effectPanelVisible(), "The puff plays where the favourite was dropped")
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertFalse(effectPanelVisible(), "The puff cleans itself up")
    }

    func testEscapeCancelsAndTheLiftedFavouriteGlidesBack() async throws {
        let (store, bar) = try makeBar(["One", "Two"])
        let start = try centre(of: button(bar, "One"))
        try drag(button(bar, "One"), from: start, through: [offset(start, 8, -8), offset(start, 40, -160)], escape: true)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertTrue(effectPanelVisible(), "The lifted copy glides back to its slot")
        }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(effectPanelVisible())
        XCTAssertEqual(store.bookmarks.map(\.title), ["One", "Two"])
    }

    func testDropInTheMarginAroundTheBarKeepsTheFavourite() async throws {
        let (store, bar) = try makeBar(["One", "Two"])
        let start = try centre(of: button(bar, "Two"))
        try drag(button(bar, "Two"), from: start, through: [offset(start, 8, -8), offset(start, 10, -30)])
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(store.bookmarks.map(\.title), ["One", "Two"])
    }

    func testDraggingAlongTheBarStillReorders() async throws {
        let (store, bar) = try makeBar(["One", "Two"])
        let start = try centre(of: button(bar, "One"))
        let end = try centre(of: button(bar, "Two"))
        try drag(button(bar, "One"), from: start, through: [offset(start, 10, 0), offset(end, 40, 0)])
        try await waitUntil { store.bookmarks.first?.title == "Two" }
        XCTAssertEqual(store.bookmarks.map(\.title), ["Two", "One"])
    }

    func testAClickWithoutMovingOpensTheFavourite() throws {
        var opened: [String] = []
        let (_, bar) = try makeBar(["One"]) { opened.append($0) }
        let start = try centre(of: button(bar, "One"))
        try drag(button(bar, "One"), from: start, through: [start])
        XCTAssertEqual(opened, ["https://site0.example/"])
    }

    // MARK: - Helpers

    private func makeBar(_ titles: [String], navigate: @escaping (String) -> Void = { _ in }) throws
        -> (BookmarkStore, FavouritesBar) {
        suite = "FavouritesDragTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = BookmarkStore(defaults: defaults)
        for (index, title) in titles.enumerated() {
            XCTAssertTrue(store.addPage(title: title, url: "https://site\(index).example/", isStartPage: false))
        }
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 800, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let bar = FavouritesBar(frame: NSRect(x: 0, y: 240, width: 800, height: 29))
        window.contentView?.addSubview(bar)
        bar.configure(store: store, tint: .labelColor, navigate: navigate, edit: {})
        window.orderFrontRegardless()
        self.window = window
        return (store, bar)
    }

    private func button(_ bar: FavouritesBar, _ title: String) throws -> FavouriteButton {
        let buttons = (bar.documentView?.subviews ?? []).compactMap { $0 as? FavouriteButton }
        return try XCTUnwrap(buttons.first { $0.title == title })
    }

    private func centre(of button: FavouriteButton) -> NSPoint {
        button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
    }

    private func offset(_ point: NSPoint, _ dx: CGFloat, _ dy: CGFloat) -> NSPoint {
        NSPoint(x: point.x + dx, y: point.y + dy)
    }

    private func event(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
        let window = try XCTUnwrap(window)
        return try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        ))
    }

    /// Presses at `start`, moves through every point and releases on the last,
    /// or presses Escape there instead.
    private func drag(_ button: FavouriteButton, from start: NSPoint, through points: [NSPoint],
                      escape: Bool = false) throws {
        let window = try XCTUnwrap(window)
        let last = try XCTUnwrap(points.last)
        for point in points.dropLast() {
            NSApp.postEvent(try event(.leftMouseDragged, at: point), atStart: false)
        }
        if escape {
            NSApp.postEvent(try event(.leftMouseDragged, at: last), atStart: false)
            let key = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: last,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            ))
            NSApp.postEvent(key, atStart: false)
        } else {
            NSApp.postEvent(try event(.leftMouseUp, at: last), atStart: false)
        }
        button.mouseDown(with: try event(.leftMouseDown, at: start))
    }

    /// The lifted copy and the puff are click-through panels above the menu bar.
    private func effectPanelVisible() -> Bool {
        NSApp.windows.contains { $0 is NSPanel && $0.ignoresMouseEvents && $0.isVisible && $0.level == .popUpMenu }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
