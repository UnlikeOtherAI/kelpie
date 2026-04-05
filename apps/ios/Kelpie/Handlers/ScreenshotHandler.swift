import WebKit

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

        let config = WKSnapshotConfiguration()
        if !fullPage {
            config.rect = webView.bounds
        }

        do {
            let image = try await webView.takeSnapshot(configuration: config)
            let data: Data?
            if format == "jpeg" {
                let quality = (body["quality"] as? Double ?? 80) / 100.0
                data = image.jpegData(compressionQuality: quality)
            } else {
                data = image.pngData()
            }
            guard let imageData = data else {
                return errorResponse(code: "SCREENSHOT_FAILED", message: "Failed to encode image")
            }
            return successResponse([
                "image": imageData.base64EncodedString(),
                "width": Int(image.size.width * image.scale),
                "height": Int(image.size.height * image.scale),
                "format": format,
            ])
        } catch {
            return errorResponse(code: "SCREENSHOT_FAILED", message: error.localizedDescription)
        }
    }
}
