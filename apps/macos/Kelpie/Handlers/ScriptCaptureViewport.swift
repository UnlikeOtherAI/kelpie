import CoreGraphics
import Foundation

/// CSS client coordinates remain separate from document-origin frame coherence.
struct ScriptCaptureViewport: Equatable {
    let bounds: CGSize
    let layout: CGSize
    let client: CGSize
    let visible: CGRect
    let scale: CGFloat
    let pixelRatio: CGFloat
    let pageOrigin: CGPoint

    var metadata: [String: Any] { ["width": layout.width, "height": layout.height] }

    var displayScale: CGFloat { bounds.width / layout.width * scale }

    func displayPoint(_ css: CGPoint) -> CGPoint {
        CGPoint(x: (css.x - visible.minX) * bounds.width / layout.width * scale,
                y: (css.y - visible.minY) * bounds.height / layout.height * scale)
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

    /// A new document may add or remove a classic scrollbar without resizing the canvas.
    func acceptsScrollbarTransition(to other: Self, documentChanged: Bool) -> Bool {
        guard documentChanged, bounds == other.bounds, layout == other.layout,
              scale == 1, other.scale == scale, pixelRatio == other.pixelRatio else { return false }
        func explained(_ layout: CGFloat, _ first: CGFloat, _ second: CGFloat, _ visualFirst: CGFloat, _ visualSecond: CGFloat) -> Bool {
            let occupancyA = layout - first
            let occupancyB = layout - second
            return occupancyA >= 0 && occupancyA <= 64 && occupancyB >= 0 && occupancyB <= 64 &&
                abs(visualFirst - first) < 0.01 && abs(visualSecond - second) < 0.01 &&
                abs((visualSecond - visualFirst) - (second - first)) < 0.01
        }
        return explained(layout.width, client.width, other.client.width, visible.width, other.visible.width) &&
            explained(layout.height, client.height, other.client.height, visible.height, other.visible.height)
    }

    /// Legal scrolling/panning between frames does not change the recording canvas.
    func sameGeometry(as other: Self) -> Bool {
        bounds == other.bounds && layout == other.layout && visible.size == other.visible.size &&
            scale == other.scale && pixelRatio == other.pixelRatio
    }
}
