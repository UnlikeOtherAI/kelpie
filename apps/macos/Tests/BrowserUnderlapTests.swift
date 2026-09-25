import AppKit
import WebKit
import XCTest
@testable import Kelpie

final class BrowserUnderlapTests: XCTestCase {
    @MainActor
    func testWebKitUnderlapPreservesVisibleViewportAndSnapshot() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native underlap requires macOS 26") }
        let renderer = WKWebViewRenderer()
        defer { renderer.invalidate() }
        let webView = try XCTUnwrap(renderer.makeView() as? WKWebView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 505), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        webView.obscuredContentInsets = NSEdgeInsets(top: 105, left: 0, bottom: 0, right: 0)
        webView.loadHTMLString("""
        <style>body{margin:0;height:2000px}a{display:block;height:40px;background:red}header{position:sticky;top:0;height:20px;background:blue}</style>
        <a id='target' href='https://example.org/target'>Target</a><header>Sticky</header>
        """, baseURL: URL(string: "https://example.org"))
        for _ in 0..<100 {
            if (try? await webView.evaluateJavaScript("!!document.getElementById('target')")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        _ = try await webView.callAsyncJavaScript(
            "await new Promise(requestAnimationFrame); await new Promise(requestAnimationFrame); return true",
            arguments: [:], in: nil, contentWorld: .page
        )
        let size = try await webView.evaluateJavaScript("[innerWidth, innerHeight, document.getElementById('target').getBoundingClientRect().top, document.elementFromPoint(10, 10).id]")
        let values = try XCTUnwrap(size as? [Any])
        XCTAssertEqual(values[0] as? Int, 400)
        XCTAssertEqual(values[1] as? Int, 400)
        XCTAssertEqual(values[2] as? Int, 0)
        XCTAssertEqual(values[3] as? String, "target")
        let hoveredLink = try await renderer.evaluateJS(RendererHoverTracker.hitTestScript(x: 10, y: 10))
        XCTAssertEqual(hoveredLink as? String, "https://example.org/target")
        let emptyHover = try await renderer.evaluateJS(RendererHoverTracker.hitTestScript(x: 10, y: 100))
        XCTAssertEqual(emptyHover as? String, "")
        let snapshot = try await renderer.takeSnapshot()
        XCTAssertEqual(snapshot.size.width, 400)
        XCTAssertEqual(snapshot.size.height, 400)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(snapshot.tiffRepresentation)))
        let pixel = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 10)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(pixel.redComponent, 0.8)
        XCTAssertLessThan(pixel.blueComponent, 0.2)

        // Collapsed chrome has a smaller inset, with the same visible CSS/screenshot contract.
        webView.setFrameSize(NSSize(width: 400, height: 432))
        webView.obscuredContentInsets.top = 32
        _ = try await webView.callAsyncJavaScript(
            "await new Promise(requestAnimationFrame); await new Promise(requestAnimationFrame); return true",
            arguments: [:], in: nil, contentWorld: .page
        )
        let collapsedHeight = try await webView.evaluateJavaScript("innerHeight")
        XCTAssertEqual(collapsedHeight as? Int, 400)
        let collapsedSnapshot = try await renderer.takeSnapshot()
        XCTAssertEqual(collapsedSnapshot.size.height, 400)
    }
}
