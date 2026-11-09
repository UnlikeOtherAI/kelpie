import XCTest
import AppKit
import WebKit
@testable import KelpieBrowser

@MainActor
final class StartPageTests: XCTestCase {
    func testPreviewKeepsTheTopOfThePageAtTheCardShape() throws {
        // A 2x snapshot of a 900-by-415-point viewport, wider than 16:10.
        let snapshot = try image(width: 1800, height: 830) { context in
            NSColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1800, height: 830))
            NSColor.systemBlue.setFill()
            context.fill(CGRect(x: 300, y: 700, width: 600, height: 80))
        }
        let preview = try XCTUnwrap(SitePreviewCache.preview(from: snapshot))
        XCTAssertEqual(preview.width, 640)
        XCTAssertEqual(preview.height, 400)
    }

    func testSmallSnapshotsAreNotUpscaled() throws {
        let snapshot = try image(width: 320, height: 400) { context in
            NSColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 400))
            NSColor.black.setFill()
            context.fill(CGRect(x: 10, y: 380, width: 50, height: 10))
        }
        let preview = try XCTUnwrap(SitePreviewCache.preview(from: snapshot))
        XCTAssertEqual(preview.width, 320)
        XCTAssertEqual(preview.height, 200)
    }

    func testBlankSnapshotIsDiscarded() throws {
        let snapshot = try image(width: 800, height: 500) { context in
            NSColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 500))
        }
        XCTAssertNil(SitePreviewCache.preview(from: snapshot))
    }

    func testPreviewFilesUseTheDesktopHexKeys() {
        XCTAssertEqual(SitePreviewCache.key(forHost: "Example.COM"), "6578616d706c652e636f6d")
        XCTAssertEqual(SitePreviewCache.host(forKey: "6578616d706c652e636f6d"), "example.com")
        XCTAssertNil(SitePreviewCache.host(forKey: "657"))
        XCTAssertNil(SitePreviewCache.host(forKey: "zz"))
    }

    func testStartPageSitesAreWebPagesCaptionedByDomain() throws {
        XCTAssertNil(StartPageSite(url: "javascript:alert(1)", title: "x"))
        XCTAssertNil(StartPageSite(url: "kelpie://start", title: "x"))
        let site = try XCTUnwrap(StartPageSite(url: "https://www.BBC.co.uk/news", title: "BBC News"))
        XCTAssertEqual(site.host, "www.bbc.co.uk")
        XCTAssertEqual(site.domain, "bbc.co.uk")
    }

    /// A window replaces the renderer's single state callback with its own; the
    /// store's routine is what both callbacks run, so it alone must record the
    /// visit.
    func testRendererStateChangeRecordsHistory() async throws {
        let keys = ["sessionTabs", "sessionTabURLs", "sessionActiveIndex"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        SessionStore.clear()
        let store = TabStore()
        defer {
            store.tabs.forEach { $0.renderer.invalidate() }
            for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
        }
        let tab = try XCTUnwrap(store.activeTab)
        tab.renderer.onStateChange = nil
        let url = "https://start-page-history.example/"
        let view = try XCTUnwrap(tab.renderer.makeView() as? WKWebView)
        view.loadHTMLString("<title>Visited</title><p>Visited</p>", baseURL: URL(string: url))
        for _ in 0..<200 {
            if tab.renderer.currentURL?.absoluteString == url, !tab.renderer.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        store.rendererStateChanged(tab)
        let entry = try XCTUnwrap(HistoryStore.shared.entries.first { $0.url == url })
        XCTAssertEqual(tab.currentURL, url)
        HistoryStore.shared.remove(id: entry.id)
    }

    private func image(width: Int, height: Int, draw: (CGContext) -> Void) throws -> NSImage {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }
}
