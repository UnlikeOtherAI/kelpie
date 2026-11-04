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

/// A non-interactive puff replaces the deprecated AppKit animation API.
@MainActor
private enum FavouritePuff {
    static func show(at point: NSPoint) {
        let panel = NSPanel(
            contentRect: NSRect(x: point.x - 36, y: point.y - 36, width: 72, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 72, height: 72))
        view.wantsLayer = true
        panel.contentView = view
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4
            let cloud = CALayer()
            cloud.frame = CGRect(x: 28 + cos(angle) * 9, y: 28 + sin(angle) * 9, width: 16, height: 16)
            cloud.cornerRadius = 8
            cloud.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.65).cgColor
            view.layer?.addSublayer(cloud)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let spread = CABasicAnimation(keyPath: "position")
                spread.fromValue = cloud.position
                spread.toValue = CGPoint(x: 36 + cos(angle) * 25, y: 36 + sin(angle) * 25)
                spread.duration = 0.4
                cloud.add(spread, forKey: "spread")
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.8
            fade.toValue = 0
            fade.duration = 0.4
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            cloud.add(fade, forKey: "fade")
        }
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { panel.close() }
    }
}
