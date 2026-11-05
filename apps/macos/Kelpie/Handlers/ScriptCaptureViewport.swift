import CoreGraphics
import Foundation

/// CSS client coordinates remain separate from document-origin frame coherence.
struct ScriptCaptureViewport: Equatable {
    let bounds: CGSize
    let layout: CGSize
    let visible: CGRect
    let scale: CGFloat
    let pixelRatio: CGFloat
    let pageOrigin: CGPoint

    var metadata: [String: Any] { ["width": layout.width, "height": layout.height] }

    func displayPoint(_ css: CGPoint) -> CGPoint {
        CGPoint(x: (css.x - visible.minX) * bounds.width / visible.width,
                y: (css.y - visible.minY) * bounds.height / visible.height)
    }

    #if DEBUG
    func debugDifference(from other: Self) {
        func flag(_ value: Bool) -> Int { value ? 1 : 0 }
        let widths = String(format: "%.2f,%.2f", Double(visible.width), Double(other.visible.width))
        let heights = String(format: "%.2f,%.2f", Double(visible.height), Double(other.visible.height))
        let comparison = "bounds=\(flag(bounds == other.bounds)) layout=\(flag(layout == other.layout)) " +
            "visible=\(flag(visible.size == other.visible.size)) scale=\(flag(scale == other.scale)) " +
            "pixel=\(flag(pixelRatio == other.pixelRatio))"
        print("[WorkflowViewport] \(comparison) widths=\(widths) heights=\(heights)")
    }
    #endif

    /// Legal scrolling/panning between frames does not change the recording canvas.
    func sameGeometry(as other: Self) -> Bool {
        bounds == other.bounds && layout == other.layout && visible.size == other.visible.size &&
            scale == other.scale && pixelRatio == other.pixelRatio
    }
}
