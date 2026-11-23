import AppKit
import WebKit
import XCTest
@testable import KelpieBrowser

/// A page's app link is cancelled and confirmed with a sheet that names the
/// requesting site and the app macOS resolved.
@MainActor
final class ExternalAppPromptTests: XCTestCase {
    func testLaunchPageAsksOnceAndNamesRequesterAndApp() async throws {
        let link = try XCTUnwrap(URL(string: "mailto:kelpie@example.com"))
        let app = try XCTUnwrap(NSWorkspace.shared.urlForApplication(toOpen: link), "This Mac needs a mail handler")
        let tab = KelpieBrowser.Tab(spec: TabSpec(dataStore: .nonPersistent()))
        let store = TabStore(isolatedTab: tab)
        let webView = tab.renderer.webView
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.close()
            store.closeAll()
        }

        webView.loadHTMLString("""
            <script>
                window.launch = () => { location.href = '\(link.absoluteString)'; };
                setTimeout(window.launch, 50);
            </script>
            """, baseURL: URL(string: "https://fixture.test"))
        try await waitFor { window.attachedSheet != nil }

        let sheet = try XCTUnwrap(window.attachedSheet)
        let texts = strings(in: sheet.contentView, of: NSTextField.self) { $0.stringValue }
        let buttons = strings(in: sheet.contentView, of: NSButton.self) { $0.title }
        let name = try XCTUnwrap(texts.first { $0.hasPrefix("Open “") })
        XCTAssertTrue(texts.contains("https://fixture.test wants to open this app."), "\(texts)")
        XCTAssertTrue(buttons.contains("Cancel"))
        XCTAssertTrue(buttons.contains { "Open “\($0.dropFirst(5))”?" == name }, "\(buttons) \(name)")
        XCTAssertEqual(webView.url?.host, "fixture.test", "The page stays loaded")
        XCTAssertFalse(app.path.isEmpty)

        window.endSheet(sheet, returnCode: .alertSecondButtonReturn)
        try await waitFor { window.attachedSheet == nil }
        _ = try await webView.evaluateJavaScript("window.launch(); 0")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(window.attachedSheet, "Without a link activation the document may ask only once")
    }

    private func strings<View: NSView>(in root: NSView?, of type: View.Type, _ value: (View) -> String) -> [String] {
        guard let root else { return [] }
        var found: [String] = []
        if let view = root as? View { found.append(value(view)) }
        for child in root.subviews { found += strings(in: child, of: type, value) }
        return found.filter { !$0.isEmpty }
    }

    private func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<160 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for the prompt")
    }
}
