import AppKit
import XCTest
@testable import Kelpie

final class BrowserChromeScrollTests: XCTestCase {
    func testDownHidesAndFirstUpwardTickReveals() {
        XCTAssertEqual(BrowserChromeScroll.collapsed(deltaX: 0, deltaY: -12), true)
        XCTAssertEqual(BrowserChromeScroll.collapsed(deltaX: 0, deltaY: 0.02), false)
    }

    func testHorizontalAndStationaryEventsDoNotChangeChrome() {
        XCTAssertNil(BrowserChromeScroll.collapsed(deltaX: 12, deltaY: -2))
        XCTAssertNil(BrowserChromeScroll.collapsed(deltaX: -12, deltaY: 2))
        XCTAssertNil(BrowserChromeScroll.collapsed(deltaX: 0, deltaY: 0))
        XCTAssertNil(BrowserChromeScroll.collapsed(deltaX: 2, deltaY: 2))
    }
}

@MainActor
final class BrowserChromeAppearanceTests: XCTestCase {
    func testPaletteKeepsLightAndDarkPagesReadable() {
        for sample in [ChromeRGB.white, ChromeRGB(red: 0.02, green: 0.03, blue: 0.12)] {
            let palette = BrowserChromePalette(sample: sample)
            let bright = max(palette.selectedTab.luminance, palette.foreground.luminance)
            let dark = min(palette.selectedTab.luminance, palette.foreground.luminance)
            XCTAssertGreaterThan((bright + 0.05) / (dark + 0.05), 4.5)
        }
    }

    func testBackgroundAndForegroundUseSameTransitionProgress() {
        let light = BrowserChromePalette.neutral
        let dark = BrowserChromePalette(sample: ChromeRGB(red: 0.02, green: 0.03, blue: 0.12))
        let halfway = light.mixed(with: dark, progress: 0.5)
        XCTAssertEqual(halfway.background.red, (light.background.red + dark.background.red) / 2, accuracy: 0.001)
        XCTAssertEqual(halfway.foreground.red, (light.foreground.red + dark.foreground.red) / 2, accuracy: 0.001)
        XCTAssertEqual(light.mixed(with: dark, progress: 1).background.red, dark.background.red, accuracy: 0.001)
    }

    func testVerticalEllipsisIsCenteredInItsCanvas() throws {
        let image = try XCTUnwrap(ToolbarIcon.image(systemName: "ellipsis.vertical"))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                xs.append(x)
                ys.append(y)
            }
        }
        XCTAssertEqual(Double(try XCTUnwrap(xs.min()) + XCTUnwrap(xs.max())) / 2, Double(bitmap.pixelsWide - 1) / 2, accuracy: 1)
        XCTAssertEqual(Double(try XCTUnwrap(ys.min()) + XCTUnwrap(ys.max())) / 2, Double(bitmap.pixelsHigh - 1) / 2, accuracy: 1)
    }

    func testNativeStripPreservesPageColor() throws {
        let image = NSImage(size: NSSize(width: 64, height: 4), flipped: false) { rect in
            NSColor(srgbRed: 0.08, green: 0.12, blue: 0.24, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let sample = try XCTUnwrap(BrowserChromeSampler.backgroundColor(image))
        XCTAssertEqual(sample.red, 0.08, accuracy: 0.02)
        XCTAssertEqual(sample.green, 0.12, accuracy: 0.02)
        XCTAssertEqual(sample.blue, 0.24, accuracy: 0.02)
    }
}

@MainActor
final class BrowserChromeSamplingTests: XCTestCase {
    func testBrightHeaderTextDoesNotWashOutDarkBackground() throws {
        let image = NSImage(size: NSSize(width: 64, height: 4), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 16, height: 4).fill()
            return true
        }
        let sample = try XCTUnwrap(BrowserChromeSampler.backgroundColor(image))
        XCTAssertLessThan(sample.luminance, 0.01)
    }
}
