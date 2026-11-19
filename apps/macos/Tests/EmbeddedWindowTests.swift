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

    func testEachWindowDisplaysItsOwnActiveWebKitTab() async {
        let server = ServerState()
        let engine = RendererState()
        engine.activeEngine = .webkit
        let first = KelpieBrowser.Tab(spec: TabSpec(persistent: false, dataStore: .nonPersistent()))
        let second = KelpieBrowser.Tab(spec: TabSpec(persistent: false, dataStore: .nonPersistent()))
        first.isStartPage = false
        second.isStartPage = false
        server.setActiveWebKitRenderer(second.renderer)

        let firstWindow = makeRendererWindow(for: first, server: server, engine: engine)
        let secondWindow = makeRendererWindow(for: second, server: server, engine: engine)
        defer {
            firstWindow.contentViewController = nil
            secondWindow.contentViewController = nil
        }

        XCTAssertTrue(first.renderer.makeView().window === firstWindow)
        XCTAssertTrue(second.renderer.makeView().window === secondWindow)
        XCTAssertFalse(first.renderer.makeView().isHidden)
        XCTAssertFalse(second.renderer.makeView().isHidden)
    }

    private func makeRendererWindow(for tab: KelpieBrowser.Tab, server: ServerState, engine: RendererState) -> NSWindow {
        let window = NSWindow()
        window.contentViewController = NSHostingController(rootView:
            RendererContainerView(
                chromeAppearance: BrowserChromeAppearance(),
                serverState: server,
                rendererState: engine,
                tabStore: TabStore(isolatedTab: tab)
            )
            .frame(width: 320, height: 200)
        )
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    private func awaitRegistration(_ id: String, window: NSWindow) async {
        for _ in 0..<50 {
            if WindowRegistry.shared.entry(for: id)?.window === window { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
