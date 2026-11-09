import AppKit

/// The lifted copy of a favourite that follows the pointer while it is dragged
/// along or off the favourites bar.
///
/// A borderless, click-through panel above the browser window: the item on a
/// popover-material chip with a shadow, and a red remove badge once the
/// pointer is far enough from the bar that dropping removes it. Mirrors
/// `DragGhost` in the Windows favourites bar.
@MainActor
final class FavouriteDragGhost {
    private static let margin: CGFloat = 10

    private let panel: NSPanel
    private let chip = NSVisualEffectView()
    private let badge = CAShapeLayer()
    /// Where the pointer holds the item, from the item's bottom-left corner.
    private let grab: NSPoint
    private var removing = false

    init(title: String, isFolder: Bool, itemSize: NSSize, grab: NSPoint, appearance: NSAppearance?) {
        self.grab = grab
        let size = NSSize(width: itemSize.width + 12, height: max(itemSize.height, 26))
        let frame = NSRect(x: 0, y: 0, width: size.width + Self.margin * 2, height: size.height + Self.margin * 2)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.appearance = appearance

        let container = NSView(frame: frame)
        container.wantsLayer = true
        chip.frame = NSRect(x: Self.margin, y: Self.margin, width: size.width, height: size.height)
        chip.material = .popover
        chip.blendingMode = .behindWindow
        chip.state = .active
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 8
        chip.layer?.masksToBounds = true
        chip.layer?.borderWidth = 0.5
        chip.layer?.borderColor = NSColor.separatorColor.cgColor
        container.addSubview(chip)

        let icon = NSImageView(image: NSImage(systemSymbolName: isFolder ? "folder" : "bookmark",
                                              accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .labelColor
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.frame = chip.bounds
        stack.autoresizingMask = [.width, .height]
        chip.addSubview(stack)

        // A red disc with a white minus, overlapping the chip's top-right corner.
        let diameter: CGFloat = 16
        badge.frame = NSRect(x: chip.frame.maxX - diameter * 0.7, y: chip.frame.maxY - diameter * 0.7,
                             width: diameter, height: diameter)
        badge.path = CGPath(ellipseIn: badge.bounds, transform: nil)
        badge.fillColor = NSColor.systemRed.cgColor
        badge.strokeColor = NSColor.white.cgColor
        badge.lineWidth = 1.5
        let minus = CAShapeLayer()
        minus.frame = badge.bounds
        let line = CGMutablePath()
        line.move(to: CGPoint(x: diameter * 0.3, y: diameter / 2))
        line.addLine(to: CGPoint(x: diameter * 0.7, y: diameter / 2))
        minus.path = line
        minus.strokeColor = NSColor.white.cgColor
        minus.lineWidth = 2
        minus.lineCap = .round
        badge.addSublayer(minus)
        badge.opacity = 0
        container.layer?.addSublayer(badge)

        panel.contentView = container
    }

    func show(at screenPoint: NSPoint) {
        place(at: screenPoint)
        panel.alphaValue = 0.97
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    /// Follows the pointer; `removing` shows the remove badge and dims the chip.
    func move(to screenPoint: NSPoint, removing: Bool) {
        place(at: screenPoint)
        guard removing != self.removing else { return }
        self.removing = removing
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        badge.opacity = removing ? 1 : 0
        CATransaction.commit()
        panel.alphaValue = removing ? 0.82 : 0.97
    }

    /// Glides back over the item's slot, then disappears. Used when a drag is
    /// cancelled.
    func flyBack(to itemScreenFrame: NSRect) {
        badge.opacity = 0
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return close() }
        var target = panel.frame
        target.origin = NSPoint(x: itemScreenFrame.minX - Self.margin - 6,
                                y: itemScreenFrame.midY - panel.frame.height / 2)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0.6
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.close() }
        })
    }

    /// Fades out where it is. Used when the item lands somewhere on the bar.
    func fadeOut() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return close() }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.close() }
        })
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    private func place(at screenPoint: NSPoint) {
        panel.setFrameOrigin(NSPoint(x: screenPoint.x - grab.x - Self.margin - 6,
                                     y: screenPoint.y - grab.y - Self.margin))
    }
}
