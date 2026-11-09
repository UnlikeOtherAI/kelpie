import AppKit

@MainActor
enum FavouriteRemoval {
    static func remove(_ id: UUID, from store: BookmarkStore, undo: UndoManager?, puffAt point: NSPoint? = nil) {
        let generation = store.generation
        Task {
            do {
                try await store.removeWithUndo(id: id)
                guard generation == store.generation else { return }
                undo?.removeAllActions(withTarget: store)
                undo?.registerUndo(withTarget: store) { target in
                    Task { @MainActor in
                        guard target.generation == generation else { return }
                        try? await target.undoLastRemoval(expectedRoot: id)
                    }
                }
                undo?.setActionName("Remove Favourite")
                if let point { FavouritePuff.show(at: point) }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not remove favourite"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}

/// The cloud that bursts where a favourite is dropped off the bar.
///
/// A click-through panel of soft billows that swell outwards and fade, with a
/// few specks thrown further out. The billow layout, timing and colours mirror
/// `ShowRemovalPuff` in the Windows favourites bar. Reduce Motion keeps a
/// brief, still fade instead of the expanding cloud.
@MainActor
private enum FavouritePuff {
    private struct Billow {
        let angle: CGFloat     // Degrees.
        let distance: CGFloat  // Fraction of the extent travelled.
        let startRadius: CGFloat
        let endRadius: CGFloat
        let delay: CGFloat     // Fraction of the animation before it moves.
    }

    private static let extent: CGFloat = 76
    private static let duration: CFTimeInterval = 0.56
    private static let billows: [Billow] = [
        Billow(angle: 0, distance: 0, startRadius: 0.26, endRadius: 0.40, delay: 0),
        Billow(angle: -8, distance: 0.52, startRadius: 0.18, endRadius: 0.27, delay: 0),
        Billow(angle: 34, distance: 0.58, startRadius: 0.16, endRadius: 0.25, delay: 0.03),
        Billow(angle: 78, distance: 0.50, startRadius: 0.19, endRadius: 0.28, delay: 0.01),
        Billow(angle: 118, distance: 0.60, startRadius: 0.15, endRadius: 0.24, delay: 0.04),
        Billow(angle: 160, distance: 0.54, startRadius: 0.18, endRadius: 0.27, delay: 0.02),
        Billow(angle: 205, distance: 0.57, startRadius: 0.16, endRadius: 0.26, delay: 0.03),
        Billow(angle: 246, distance: 0.50, startRadius: 0.19, endRadius: 0.28, delay: 0),
        Billow(angle: 286, distance: 0.60, startRadius: 0.15, endRadius: 0.24, delay: 0.05),
        Billow(angle: 326, distance: 0.53, startRadius: 0.17, endRadius: 0.26, delay: 0.02)
    ]
    private static let specks: [CGFloat] = [20, 82, 140, 196, 258, 312]

    static func show(at point: NSPoint) {
        let side = extent * 2
        let panel = NSPanel(
            contentRect: NSRect(x: point.x - extent, y: point.y - extent, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let view = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.wantsLayer = true
        panel.contentView = view
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let centre = CGPoint(x: extent, y: extent)
        // The billows share one shadow and one fade, so they merge into a
        // single cloud instead of a cluster of bubbles.
        let cloud = CALayer()
        cloud.frame = view.bounds
        cloud.shadowColor = NSColor(red: 40 / 255, green: 44 / 255, blue: 60 / 255, alpha: 1).cgColor
        cloud.shadowOpacity = 0.22
        cloud.shadowRadius = 2
        cloud.shadowOffset = CGSize(width: 0, height: -extent * 0.05)
        cloud.opacity = 0
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = still ? [0.9, 0] : [0, 1, 0.8, 0]
        fade.keyTimes = still ? [0, 1] : [0, 0.1, 0.5, 1]
        fade.duration = still ? 0.25 : duration
        cloud.add(fade, forKey: "fade")
        for billow in billows {
            cloud.addSublayer(self.billow(billow, centre: centre, still: still))
        }
        view.layer?.addSublayer(cloud)
        if !still {
            for angle in specks { view.layer?.addSublayer(speck(angle, centre: centre)) }
        }
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + (still ? 0.25 : duration)) { panel.close() }
    }

    /// One billow: the cloud's cool grey body with a lit top-left.
    private static func billow(_ billow: Billow, centre: CGPoint, still: Bool) -> CALayer {
        let radians = billow.angle * .pi / 180
        let finalRadius = extent * (still ? billow.startRadius : billow.endRadius)
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: finalRadius * 2, height: finalRadius * 2)
        layer.cornerRadius = finalRadius
        layer.backgroundColor = NSColor(red: 222 / 255, green: 226 / 255, blue: 235 / 255, alpha: 0.95).cgColor
        let light = CAGradientLayer()
        light.type = .radial
        light.colors = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        light.startPoint = CGPoint(x: 0.35, y: 0.65)
        light.endPoint = CGPoint(x: 1, y: 0)
        light.frame = layer.bounds
        light.cornerRadius = finalRadius
        light.masksToBounds = true
        layer.addSublayer(light)
        let end = CGPoint(x: centre.x + cos(radians) * billow.distance * extent,
                          y: centre.y + sin(radians) * billow.distance * extent)
        layer.position = end
        guard !still else { return layer }

        let delay = CFTimeInterval(billow.delay) * duration
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = billow.startRadius / billow.endRadius
        grow.toValue = 1
        let travel = CABasicAnimation(keyPath: "position")
        travel.fromValue = CGPoint(x: centre.x + cos(radians) * billow.distance * extent * 0.2,
                                   y: centre.y + sin(radians) * billow.distance * extent * 0.2)
        travel.toValue = end
        let group = CAAnimationGroup()
        group.animations = [grow, travel]
        group.beginTime = CACurrentMediaTime() + delay
        group.duration = duration - delay
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "billow")
        return layer
    }

    private static func speck(_ angle: CGFloat, centre: CGPoint) -> CALayer {
        let radians = angle * .pi / 180
        let radius = extent * 0.045
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        layer.cornerRadius = radius
        layer.backgroundColor = NSColor(red: 214 / 255, green: 218 / 255, blue: 228 / 255, alpha: 0.86).cgColor
        let end = CGPoint(x: centre.x + cos(radians) * extent * 0.9, y: centre.y + sin(radians) * extent * 0.9)
        layer.position = end
        layer.opacity = 0
        let travel = CABasicAnimation(keyPath: "position")
        travel.fromValue = CGPoint(x: centre.x + cos(radians) * extent * 0.35, y: centre.y + sin(radians) * extent * 0.35)
        travel.toValue = end
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.86, 0]
        fade.keyTimes = [0, 0.15, 0.85]
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.5
        let group = CAAnimationGroup()
        group.animations = [travel, fade, shrink]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        layer.add(group, forKey: "speck")
        return layer
    }
}
