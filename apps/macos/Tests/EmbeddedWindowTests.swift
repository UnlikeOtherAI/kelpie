import AppKit
import SwiftUI
import XCTest
@testable import KelpieBrowser

@MainActor
final class EmbeddedWindowTests: XCTestCase {
    func testFullscreenCannotControlContainingAppWindow() async {
        let id = UUID().uuidString
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        WindowRegistry.shared.register(id: id, window: window, tabStore: TabStore(), ownsWindowChrome: false)
        defer { WindowRegistry.shared.unregister(id: id) }
        let router = Router()
        BrowserManagementHandler(context: HandlerContext(), viewportState: ViewportState()).register(on: router)

        for method in ["set-fullscreen", "get-fullscreen"] {
            let response = await router.handle(method: method, body: ["windowId": id, "enabled": true]).json
            XCTAssertEqual(response["success"] as? Bool, false)
            XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? String, "PLATFORM_NOT_SUPPORTED")
        }
        XCTAssertFalse(window.styleMask.contains(.fullScreen))
        XCTAssertNil(WindowRegistry.shared.entry(for: id)?.ownedWindow)
    }

    func testStandaloneEntryRetainsWindowAuthority() {
        let id = UUID().uuidString
        let window = NSWindow()
        WindowRegistry.shared.register(id: id, window: window, tabStore: TabStore(), ownsWindowChrome: true)
        defer { WindowRegistry.shared.unregister(id: id) }
        XCTAssertTrue(WindowRegistry.shared.entry(for: id)?.ownedWindow === window)
    }

    func testReparentingUpdatesRegisteredWindow() async {
        let id = UUID().uuidString
        let store = TabStore()
        let first = NSWindow()
        let second = NSWindow()
        let controller = NSHostingController(rootView:
            WindowRegistrationBridge(windowId: id, tabStore: store, ownsWindowChrome: false)
                .frame(width: 20, height: 20)
        )
        defer {
            first.contentViewController = nil
            second.contentViewController = nil
            WindowRegistry.shared.unregister(id: id)
        }
        first.contentViewController = controller
        await awaitRegistration(id, window: first)
        XCTAssertTrue(WindowRegistry.shared.entry(for: id)?.window === first)
        first.contentViewController = nil
        second.contentViewController = controller
        await awaitRegistration(id, window: second)
        XCTAssertTrue(WindowRegistry.shared.entry(for: id)?.window === second)
        XCTAssertTrue(WindowRegistry.shared.entry(for: id)?.tabStore === store)
        XCTAssertNil(WindowRegistry.shared.entry(for: id)?.ownedWindow)
    }

    private func awaitRegistration(_ id: String, window: NSWindow) async {
        for _ in 0..<50 {
            if WindowRegistry.shared.entry(for: id)?.window === window { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
