import AppKit

/// Draw into a fixed canvas: rotating an Auto Layout view displaces its frame.
enum ToolbarIcon {
    static func image(systemName: String) -> NSImage? {
        guard systemName == "ellipsis.vertical" else {
            return NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        }
        let image = NSImage(size: NSSize(width: 19, height: 19), flipped: false) { _ in
            NSColor.black.setFill()
            for y in [4.5, 9.5, 14.5] {
                NSBezierPath(ovalIn: NSRect(x: 8.25, y: y - 1.25, width: 2.5, height: 2.5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
