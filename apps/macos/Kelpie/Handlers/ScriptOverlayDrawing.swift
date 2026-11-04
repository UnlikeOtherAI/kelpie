import CoreGraphics
import Foundation

struct ScriptOverlayMarker {
    var point: CGPoint
    let started: TimeInterval
    let duration: TimeInterval
    let radius: CGFloat
    let color: CGColor
    let wobble: Bool
    let fade: Bool
}

/// One CoreGraphics compositor serves the live native overlay and exported frames on Apple platforms.
enum ScriptOverlayDrawing {
    static func color(_ hex: String) -> CGColor {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x3B82F6
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGColor(
            colorSpace: space,
            components: [
                CGFloat((value >> 16) & 255) / 255,
                CGFloat((value >> 8) & 255) / 255,
                CGFloat(value & 255) / 255,
                1
            ]
        ) ?? CGColor(gray: 0, alpha: 1)
    }

    static func path(from start: CGPoint, to end: CGPoint, progress: Double, curve: String) -> CGPoint {
        let value = kelpie_script_pointer_position(
            KelpieScriptPoint(x: Double(start.x), y: Double(start.y)),
            KelpieScriptPoint(x: Double(end.x), y: Double(end.y)),
            curve == "c" ? 0 : 1,
            progress
        )
        return CGPoint(x: value.x, y: value.y)
    }

    static func draw(
        in graphics: CGContext,
        size: CGSize,
        viewport: CGSize,
        pointer: CGPoint?,
        marker: ScriptOverlayMarker?,
        now: TimeInterval,
        flipped: Bool = false
    ) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        graphics.saveGState()
        defer { graphics.restoreGState() }
        if !flipped {
            graphics.translateBy(x: 0, y: size.height)
            graphics.scaleBy(x: 1, y: -1)
        }
        graphics.scaleBy(x: size.width / viewport.width, y: size.height / viewport.height)
        if let pointer {
            graphics.setFillColor(CGColor(gray: 1, alpha: 1))
            graphics.setStrokeColor(CGColor(gray: 0, alpha: 1))
            graphics.setLineWidth(1.5)
            graphics.move(to: pointer)
            graphics.addLine(to: CGPoint(x: pointer.x + 5, y: pointer.y + 19))
            graphics.addLine(to: CGPoint(x: pointer.x + 10, y: pointer.y + 12))
            graphics.addLine(to: CGPoint(x: pointer.x + 18, y: pointer.y + 10))
            graphics.closePath()
            graphics.drawPath(using: .fillStroke)
        }
        guard let marker, now >= marker.started else { return }
        let fraction = kelpie_script_progress((now - marker.started) * 1000, marker.duration * 1000)
        let state = kelpie_script_tap_presentation(fraction, marker.wobble ? 1 : 0, marker.fade ? 1 : 0)
        guard state.alpha > 0 else { return }
        let radius = marker.radius * CGFloat(state.scale)
        graphics.setFillColor(marker.color.copy(alpha: CGFloat(state.alpha)) ?? marker.color)
        graphics.fillEllipse(in: CGRect(
            x: marker.point.x - radius,
            y: marker.point.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }
}
