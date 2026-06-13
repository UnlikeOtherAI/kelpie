import WebKit

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

/// Result of a full-page capture: the stitched image plus the CSS-pixel height
/// it vertically spans, used to make the response metadata's `imageScaleY`
/// internally consistent for full-page coordinate mapping.
private struct FullPageCapture {
    let image: UIImage
    let contentHeightCss: Int
}

/// Handles screenshot (viewport and full-page).
struct ScreenshotHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("screenshot") { body in await screenshot(body) }
    }

    @MainActor
    private func screenshot(_ body: [String: Any]) async -> [String: Any] {
        guard let webView = context.webView else {
            return errorResponse(code: "NO_WEBVIEW", message: "No WebView")
        }

        let fullPage = body["fullPage"] as? Bool ?? false
        let format = body["format"] as? String ?? "png"
        guard let resolution = ScreenshotResolution.parse(body["resolution"]) else {
            return errorResponse(code: "INVALID_PARAMS", message: "resolution must be 'native' or 'viewport'")
        }

        do {
            let image: UIImage
            var fullPageContentHeight: Int?
            if fullPage {
                let capture = try await captureFullPage(webView: webView)
                image = capture.image
                fullPageContentHeight = capture.contentHeightCss
            } else {
                image = try await captureViewport(webView: webView)
            }
            let quality = ((body["quality"] as? NSNumber)?.doubleValue ?? 80) / 100.0
            var payload = try await context.screenshotPayload(
                from: image,
                format: format,
                quality: quality,
                resolution: resolution
            )
            // For a full-page capture the image spans the whole document, so the
            // shared viewport-based `imageScaleY`/`contentHeight` are meaningless.
            // Rewrite them against the full captured CSS content height so a
            // consumer can map full-page image pixels back to CSS coordinates.
            if let contentHeight = fullPageContentHeight, contentHeight > 0,
               let imageHeight = payload["height"] as? Int {
                payload["contentHeight"] = contentHeight
                payload["imageScaleY"] = Double(imageHeight) / Double(contentHeight)
                // iOS stitches the whole page (no height cap), so it never truncates;
                // emit the key for full-page response-shape parity with Android.
                payload["truncated"] = false
            }
            return successResponse(payload)
        } catch {
            return errorResponse(code: "SCREENSHOT_FAILED", message: error.localizedDescription)
        }
    }

    /// Captures the visible viewport via WebKit's clip-to-bounds snapshot.
    @MainActor
    private func captureViewport(webView: WKWebView) async throws -> UIImage {
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        return try await webView.takeSnapshot(configuration: config)
    }

    // MARK: - Full-page capture

    /// Captures the entire scrollable page by scrolling viewport-by-viewport and
    /// stitching each snapshot into one image.
    ///
    /// `WKWebView.takeSnapshot` clips to the visible bounds and does not render
    /// off-screen content, so a single snapshot only ever covers one viewport.
    /// Driving the renderer over the shared `evaluateJS`/`takeSnapshot` surface
    /// captures the full document the same way macOS does, keeping the two
    /// platforms in parity.
    @MainActor
    private func captureFullPage(webView: WKWebView) async throws -> FullPageCapture {
        let geometry = try await measureGeometry()
        defer {
            Task { @MainActor in
                _ = try? await context.evaluateJS(
                    "window.scrollTo(\(geometry.originalScrollX), \(geometry.originalScrollY))"
                )
            }
        }

        // A single viewport already covers the page — no stitching needed. The
        // image spans exactly one viewport, so that is its CSS content height.
        if geometry.pageHeight <= geometry.viewportHeight + 1,
           geometry.pageWidth <= geometry.viewportWidth + 1 {
            let image = try await captureViewport(webView: webView)
            return FullPageCapture(image: image, contentHeightCss: Int(geometry.viewportHeight.rounded()))
        }

        let tiles = planTiles(for: geometry)
        let image = try await stitch(tiles: tiles, geometry: geometry, webView: webView)
        return FullPageCapture(image: image, contentHeightCss: Int(geometry.pageHeight.rounded()))
    }

    @MainActor
    private func measureGeometry() async throws -> FullPageGeometry {
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
        """)
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
        webView: WKWebView
    ) async throws -> UIImage {
        // Determine the device-pixel scale from the first capture so the stitched
        // canvas matches the renderer's backing resolution (Retina-aware).
        try await scroll(to: tiles[0])
        let firstSnapshot = try await captureViewport(webView: webView)
        let repWidth = Double(firstSnapshot.cgImage?.width ?? 0)
        let repHeight = Double(firstSnapshot.cgImage?.height ?? 0)
        let scaleX = repWidth > 0 && geometry.viewportWidth > 0 ? repWidth / geometry.viewportWidth : 1
        let scaleY = repHeight > 0 && geometry.viewportHeight > 0 ? repHeight / geometry.viewportHeight : 1
        let canvasWidth = max(Int((geometry.pageWidth * scaleX).rounded()), 1)
        let canvasHeight = max(Int((geometry.pageHeight * scaleY).rounded()), 1)

        // Composite in a pixel-sized CGContext so every coordinate — canvas
        // dimensions, tile origins, and per-tile CGImage extents — is in backing
        // pixels. Drawing each snapshot's CGImage (rather than UIImage.draw, whose
        // rect is in point space) keeps Retina (scale 2/3) sampling exact.
        guard let ctx = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw HandlerError.screenshotFailed
        }

        for (index, origin) in tiles.enumerated() {
            let snapshot: UIImage
            if index == 0 {
                snapshot = firstSnapshot
            } else {
                try await scroll(to: origin)
                snapshot = try await captureViewport(webView: webView)
            }
            draw(snapshot, at: origin, scaleX: scaleX, scaleY: scaleY, canvasHeight: canvasHeight, into: ctx)
        }

        guard let composited = ctx.makeImage() else {
            throw HandlerError.screenshotFailed
        }
        return UIImage(cgImage: composited)
    }

    /// Draws one viewport snapshot into the stitched canvas in pixel coordinates.
    /// The snapshot's `CGImage` carries its true backing-pixel extent, so source
    /// and destination are both in pixels — no point/pixel mismatch on Retina.
    /// `CGContext` is bottom-left origin, so the top-down `origin.y` (scaled to
    /// pixels) is flipped against the canvas height.
    @MainActor
    private func draw(
        _ snapshot: UIImage,
        at origin: CGPoint,
        scaleX: Double,
        scaleY: Double,
        canvasHeight: Int,
        into ctx: CGContext
    ) {
        guard let cgImage = snapshot.cgImage else {
            return
        }
        let pixelWidth = Double(cgImage.width)
        let pixelHeight = Double(cgImage.height)
        let destX = origin.x * scaleX
        let destTop = origin.y * scaleY
        let destY = Double(canvasHeight) - destTop - pixelHeight
        ctx.draw(cgImage, in: CGRect(x: destX, y: destY, width: pixelWidth, height: pixelHeight))
    }

    @MainActor
    private func scroll(to origin: CGPoint) async throws {
        _ = try await context.evaluateJS("window.scrollTo(\(origin.x), \(origin.y))")
        // Let the renderer paint the freshly scrolled region before snapshotting.
        try? await Task.sleep(nanoseconds: 120_000_000)
    }
}
