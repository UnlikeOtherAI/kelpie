import AppKit
import WebKit

extension WKWebViewRenderer {
    var scriptViewportRect: CGRect {
        let view = makeView()
        let top: CGFloat
        if #available(macOS 26.0, *), let webView = view as? WKWebView { top = webView.obscuredContentInsets.top } else { top = 0 }
        return CGRect(x: view.bounds.minX, y: view.bounds.minY + (view.isFlipped ? top : 0), width: view.bounds.width, height: max(0, view.bounds.height - top))
    }

    func takeScriptSnapshot(viewport: CGRect, maximumPixels: CGSize, pixelRatio: CGFloat) async throws -> NSImage {
        guard let view = makeView() as? WKWebView, scriptViewportRect.width > 0, scriptViewportRect.height > 0 else {
            throw ScriptWorkflowFailure("CAPTURE_VIEWPORT_UNAVAILABLE")
        }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: scriptViewportRect.size)
        configuration.afterScreenUpdates = true
        let width = min(maximumPixels.width, maximumPixels.height * scriptViewportRect.width / scriptViewportRect.height)
        configuration.snapshotWidth = NSNumber(value: Double(width / max(view.window?.backingScaleFactor ?? 1, 1)))
        // The caller owns the timeout fence until this actual WebKit callback retires.
        return try await withCheckedThrowingContinuation { continuation in
            view.takeSnapshot(with: configuration) { image, error in
                if let image { continuation.resume(returning: image) } else { continuation.resume(throwing: error ?? ScriptWorkflowFailure("CAPTURE_PIXEL_SOURCE_UNAVAILABLE")) }
            }
        }
    }
}
