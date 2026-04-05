import AppKit

/// Handles screenshot (viewport and full-page).
struct ScreenshotHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("screenshot") { body in await screenshot(body) }
    }

    @MainActor
    private func screenshot(_ body: [String: Any]) async -> [String: Any] {
        guard context.renderer != nil else {
            return errorResponse(code: "NO_WEBVIEW", message: "No WebView")
        }

        let format = body["format"] as? String ?? "png"

        do {
            let image = try await context.takeSnapshot()
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) else {
                return errorResponse(code: "SCREENSHOT_FAILED", message: "Failed to create bitmap")
            }

            let data: Data?
            if format == "jpeg" {
                let quality = (body["quality"] as? Double ?? 80) / 100.0
                data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
            } else {
                data = bitmap.representation(using: .png, properties: [:])
            }
            guard let imageData = data else {
                return errorResponse(code: "SCREENSHOT_FAILED", message: "Failed to encode image")
            }
            return successResponse([
                "image": imageData.base64EncodedString(),
                "width": bitmap.pixelsWide,
                "height": bitmap.pixelsHigh,
                "format": format,
            ])
        } catch {
            return errorResponse(code: "SCREENSHOT_FAILED", message: error.localizedDescription)
        }
    }
}
