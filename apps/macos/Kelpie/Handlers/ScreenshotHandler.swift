import AppKit

enum ScreenshotResolution: String {
    case native
    case viewport

    static func parse(_ raw: Any?) -> Self? {
        guard let raw else { return .native }
        guard let value = raw as? String else { return nil }
        return Self(rawValue: value)
    }
}

struct ScreenshotViewportMetrics {
    let viewportWidth: Int
    let viewportHeight: Int
    let devicePixelRatio: Double

    func metadata(
        imageWidth: Int,
        imageHeight: Int,
        format: String,
        resolution: ScreenshotResolution
    ) -> [String: Any] {
        let scaleX = viewportWidth > 0 ? Double(imageWidth) / Double(viewportWidth) : 1
        let scaleY = viewportHeight > 0 ? Double(imageHeight) / Double(viewportHeight) : 1
        return [
            "width": imageWidth,
            "height": imageHeight,
            "format": format,
            "resolution": resolution.rawValue,
            "coordinateSpace": "viewport-css-pixels",
            "viewportWidth": viewportWidth,
            "viewportHeight": viewportHeight,
            "devicePixelRatio": devicePixelRatio,
            "imageScaleX": scaleX,
            "imageScaleY": scaleY
        ]
    }
}

func bitmapRepresentation(of image: NSImage) -> NSBitmapImageRep? {
    if let data = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: data) {
        return bitmap
    }
    return nil
}

func scaledBitmapRepresentation(
    from image: NSImage,
    to resolution: ScreenshotResolution,
    using viewport: ScreenshotViewportMetrics
) -> NSBitmapImageRep? {
    guard let bitmap = bitmapRepresentation(of: image) else {
        return nil
    }
    guard resolution == .viewport else {
        return bitmap
    }
    let targetWidth = max(Int(round(Double(bitmap.pixelsWide) / max(viewport.devicePixelRatio, 1.0))), 1)
    let targetHeight = max(Int(round(Double(bitmap.pixelsHigh) / max(viewport.devicePixelRatio, 1.0))), 1)
    guard targetWidth != bitmap.pixelsWide || targetHeight != bitmap.pixelsHigh else {
        return bitmap
    }
    guard let scaled = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: targetWidth,
        pixelsHigh: targetHeight,
        bitsPerSample: bitmap.bitsPerSample,
        samplesPerPixel: bitmap.samplesPerPixel,
        hasAlpha: bitmap.hasAlpha,
        isPlanar: false,
        colorSpaceName: bitmap.colorSpaceName ?? .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return bitmap
    }
    scaled.size = NSSize(width: targetWidth, height: targetHeight)
    let source = NSImage(size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
    source.addRepresentation(bitmap)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: scaled) else {
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    source.draw(
        in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
        from: NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh),
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    return scaled
}

/// Geometry of the scrollable page, measured in CSS pixels, used to plan a
/// full-page scroll-and-stitch capture.
private struct FullPageGeometry {
    let pageWidth: Double
    let pageHeight: Double
    let viewportWidth: Double
    let viewportHeight: Double
    let originalScrollX: Double
    let originalScrollY: Double
}

/// Handles screenshot (viewport and full-page).
struct ScreenshotHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("screenshot") { body in await screenshot(body) }
    }

    @MainActor
    private func screenshot(_ body: [String: Any]) async -> [String: Any] {
        let tabId = HandlerContext.tabId(from: body)
        let fullPage = body["fullPage"] as? Bool ?? false
        let format = body["format"] as? String ?? "png"
        guard let resolution = ScreenshotResolution.parse(body["resolution"]) else {
            return errorResponse(code: "INVALID_PARAMS", message: "resolution must be 'native' or 'viewport'")
        }

        do {
            _ = try context.resolveRenderer(tabId: tabId)
            let image: NSImage
            if fullPage {
                image = try await captureFullPage(tabId: tabId)
            } else {
                image = try await context.takeSnapshot(tabId: tabId)
            }
            let quality = ((body["quality"] as? NSNumber)?.doubleValue ?? 80) / 100.0
            return successResponse(
                try await context.screenshotPayload(
                    from: image,
                    format: format,
                    quality: quality,
                    resolution: resolution,
                    tabId: tabId
                )
            )
        } catch {
            if let tabError = tabErrorResponse(from: error) { return tabError }
            return errorResponse(code: "SCREENSHOT_FAILED", message: error.localizedDescription)
        }
    }

    // MARK: - Full-page capture

    /// Captures the entire scrollable page by scrolling viewport-by-viewport and
    /// stitching each snapshot into one image.
    ///
    /// Both macOS renderers are viewport-only at this layer: `WKWebView.takeSnapshot`
    /// clips to the visible rect, and the CEF bridge's CDP `Page.captureScreenshot`
    /// is hard-clipped to the view bounds. Driving the renderer over the shared
    /// `evaluateJS`/`takeSnapshot` surface keeps this path renderer-agnostic without
    /// reaching into either engine.
    @MainActor
    private func captureFullPage(tabId: String?) async throws -> NSImage {
        let geometry = try await measureGeometry(tabId: tabId)
        defer {
            Task { @MainActor in
                _ = try? await context.evaluateJS(
                    "window.scrollTo(\(geometry.originalScrollX), \(geometry.originalScrollY))",
                    tabId: tabId
                )
            }
        }

        // A single viewport already covers the page — no stitching needed.
        if geometry.pageHeight <= geometry.viewportHeight + 1,
           geometry.pageWidth <= geometry.viewportWidth + 1 {
            return try await context.takeSnapshot(tabId: tabId)
        }

        let tiles = planTiles(for: geometry)
        return try await stitch(tiles: tiles, geometry: geometry, tabId: tabId)
    }

    @MainActor
    private func measureGeometry(tabId: String?) async throws -> FullPageGeometry {
        let result = try await context.evaluateJSReturningJSON("""
        (function() {
            var d = document.documentElement;
            var b = document.body;
            return {
                pageWidth: Math.max(d.scrollWidth, b ? b.scrollWidth : 0, window.innerWidth || 0),
                pageHeight: Math.max(d.scrollHeight, b ? b.scrollHeight : 0, window.innerHeight || 0),
                viewportWidth: Math.max(window.innerWidth || 0, 1),
                viewportHeight: Math.max(window.innerHeight || 0, 1),
                scrollX: window.scrollX || 0,
                scrollY: window.scrollY || 0
            };
        })()
        """, tabId: tabId)
        func double(_ key: String, _ fallback: Double) -> Double {
            (result[key] as? NSNumber)?.doubleValue ?? fallback
        }
        return FullPageGeometry(
            pageWidth: double("pageWidth", 1),
            pageHeight: double("pageHeight", 1),
            viewportWidth: double("viewportWidth", 1),
            viewportHeight: double("viewportHeight", 1),
            originalScrollX: double("scrollX", 0),
            originalScrollY: double("scrollY", 0)
        )
    }

    /// Top-left CSS-pixel origins of each viewport-sized tile covering the page.
    /// The last row/column is clamped so it ends flush with the page edge,
    /// keeping captures aligned even when the page is not an exact multiple of
    /// the viewport.
    private func planTiles(for geometry: FullPageGeometry) -> [CGPoint] {
        let maxX = max(geometry.pageWidth - geometry.viewportWidth, 0)
        let maxY = max(geometry.pageHeight - geometry.viewportHeight, 0)
        var origins: [CGPoint] = []
        var y = 0.0
        while true {
            let clampedY = min(y, maxY)
            var x = 0.0
            while true {
                let clampedX = min(x, maxX)
                origins.append(CGPoint(x: clampedX, y: clampedY))
                if clampedX >= maxX { break }
                x += geometry.viewportWidth
            }
            if clampedY >= maxY { break }
            y += geometry.viewportHeight
        }
        return origins
    }

    @MainActor
    private func stitch(
        tiles: [CGPoint],
        geometry: FullPageGeometry,
        tabId: String?
    ) async throws -> NSImage {
        // Determine the device-pixel scale from the first capture so the stitched
        // canvas matches the renderer's backing resolution (Retina-aware).
        try await scroll(to: tiles[0], tabId: tabId)
        let firstSnapshot = try await context.takeSnapshot(tabId: tabId)
        let firstRep = firstSnapshot.representations.first
        let repWidth = Double(firstRep?.pixelsWide ?? 0)
        let repHeight = Double(firstRep?.pixelsHigh ?? 0)
        let scaleX = repWidth > 0 && geometry.viewportWidth > 0 ? repWidth / geometry.viewportWidth : 1
        let scaleY = repHeight > 0 && geometry.viewportHeight > 0 ? repHeight / geometry.viewportHeight : 1
        let canvasWidth = max(Int((geometry.pageWidth * scaleX).rounded()), 1)
        let canvasHeight = max(Int((geometry.pageHeight * scaleY).rounded()), 1)

        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: canvasWidth,
            pixelsHigh: canvasHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw HandlerError.screenshotFailed
        }
        canvas.size = NSSize(width: canvasWidth, height: canvasHeight)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: canvas) else {
            throw HandlerError.screenshotFailed
        }
        NSGraphicsContext.current = ctx

        for (index, origin) in tiles.enumerated() {
            let snapshot: NSImage
            if index == 0 {
                snapshot = firstSnapshot
            } else {
                try await scroll(to: origin, tabId: tabId)
                snapshot = try await context.takeSnapshot(tabId: tabId)
            }
            draw(snapshot, at: origin, scaleX: scaleX, scaleY: scaleY, canvasHeight: canvasHeight)
        }

        let result = NSImage(size: NSSize(width: canvasWidth, height: canvasHeight))
        result.addRepresentation(canvas)
        return result
    }

    /// Draws one viewport snapshot into the stitched canvas. AppKit's image
    /// coordinate space is bottom-left origin, so the CSS-pixel `origin.y`
    /// (top-down) is flipped against the canvas height.
    @MainActor
    private func draw(
        _ snapshot: NSImage,
        at origin: CGPoint,
        scaleX: Double,
        scaleY: Double,
        canvasHeight: Int
    ) {
        guard let rep = snapshot.representations.first else { return }
        let pixelWidth = Double(rep.pixelsWide)
        let pixelHeight = Double(rep.pixelsHigh)
        let destX = origin.x * scaleX
        let destTop = origin.y * scaleY
        let destY = Double(canvasHeight) - destTop - pixelHeight
        snapshot.draw(
            in: NSRect(x: destX, y: destY, width: pixelWidth, height: pixelHeight),
            from: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
            operation: .copy,
            fraction: 1
        )
    }

    @MainActor
    private func scroll(to origin: CGPoint, tabId: String?) async throws {
        _ = try await context.evaluateJS(
            "window.scrollTo(\(origin.x), \(origin.y))",
            tabId: tabId
        )
        // Let the renderer paint the freshly scrolled region before snapshotting.
        try? await Task.sleep(nanoseconds: 120_000_000)
    }
}
