import AppKit

/// Shared scaling and overlay composition for captured renderer frames.
@MainActor
enum ScriptCaptureCompositor {
    static func compose(
        _ source: NSImage,
        maximumWidth: Int,
        outputSize: inout CGSize,
        draw: (CGContext, CGSize) -> Void
    ) throws -> CGImage {
        var rect = CGRect(origin: .zero, size: source.size)
        guard let image = source.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { throw ScriptCaptureError.image }
        let scale = min(Double(maximumWidth) / Double(image.width), 1920 / Double(image.height), 1)
        let width = max(2, Int(Double(image.width) * scale) / 2 * 2)
        let height = max(2, Int(Double(image.height) * scale) / 2 * 2)
        let size = CGSize(width: width, height: height)
        if outputSize != .zero, outputSize != size { throw ScriptWorkflowFailure("CAPTURE_VIEWPORT_CHANGED") }
        outputSize = size
        guard let graphics = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ScriptCaptureError.image }
        graphics.draw(image, in: CGRect(origin: .zero, size: size))
        draw(graphics, size)
        guard let composed = graphics.makeImage() else { throw ScriptCaptureError.image }
        return composed
    }
}
