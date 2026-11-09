import AppKit
import SwiftUI

struct FavouritesBarView: NSViewRepresentable {
    @ObservedObject var appearance: BrowserChromeAppearance
    @ObservedObject var store = BookmarkStore.shared
    let onNavigate: (String) -> Void
    let onEdit: () -> Void

    func makeNSView(context: Context) -> FavouritesBar { FavouritesBar() }
    func updateNSView(_ view: FavouritesBar, context: Context) {
        view.configure(store: store, tint: appearance.palette.foreground.color, navigate: onNavigate, edit: onEdit)
    }
}

/// Native buttons stay clickable after either web renderer becomes first responder.
final class FavouritesBar: NSScrollView {
    private let strip = NSView()
    private var store = BookmarkStore.shared
    private var navigate: (String) -> Void = { _ in }
    private var edit: () -> Void = {}
    private var nodes: [BookmarkStore.Bookmark] = []
    private var menuGeneration = UUID()
    private var activeMenu: NSMenu?

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        hasHorizontalScroller = false
        documentView = strip
        setAccessibilityIdentifier("browser.favourites")
    }
    required init?(coder: NSCoder) { nil }

    func configure(store: BookmarkStore, tint: NSColor, navigate: @escaping (String) -> Void, edit: @escaping () -> Void) {
        self.store = store
        self.navigate = navigate
        self.edit = edit
        if nodes != store.nodes || menuGeneration != store.generation {
            activeMenu?.cancelTracking()
            nodes = store.nodes
            menuGeneration = store.generation
            for view in strip.subviews { view.removeFromSuperview() }
            var x: CGFloat = 20
            for node in store.children(of: nil) {
                let button = FavouriteButton(title: node.title, target: nil, action: nil)
                button.nodeID = node.id
                button.isFolder = node.isFolder
                button.bezelStyle = .inline
                button.isBordered = false
                button.font = .systemFont(ofSize: 12)
                button.image = NSImage(systemSymbolName: node.isFolder ? "folder" : "bookmark", accessibilityDescription: nil)
                button.imagePosition = .imageLeading
                button.toolTip = node.isFolder ? node.title : node.url
                button.setAccessibilityIdentifier("browser.favourite.\(node.id.uuidString)")
                button.setAccessibilityLabel(node.title)
                button.activate = { [weak self, weak button] in
                    guard let self, let button else { return }
                    if node.isFolder { self.openFolder(node.id, from: button) } else { self.open(node.id) }
                }
                button.finishDrag = { [weak self] point, generation in
                    self?.drop(node.id, at: point, generation: generation) ?? .ignored
                }
                button.sourceGeneration = { [weak self] in self?.store.generation ?? UUID() }
                button.dragRect = { [weak self] in self?.screenRect ?? .zero }
                button.menu = contextMenu(for: node.id)
                let titleWidth = (node.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
                let width = min(240, max(50, titleWidth + 32))
                button.frame = NSRect(x: x, y: 0, width: width, height: 29)
                strip.addSubview(button)
                x += width + 20
            }
            strip.setFrameSize(NSSize(width: x, height: 29))
            if strip.subviews.isEmpty { strip.setFrameSize(NSSize(width: 40, height: 29)) }
        }
        for case let button as NSButton in strip.subviews { button.contentTintColor = tint }
    }

    private var screenRect: NSRect { window?.convertToScreen(convert(bounds, to: nil)) ?? .zero }

    private func open(_ id: UUID) {
        guard let node = store.nodes.first(where: { $0.id == id }), !node.isFolder,
              (try? BookmarkTree.validate(node)) != nil else { return }
        navigate(node.url)
    }

    private func openFolder(_ id: UUID, from button: NSButton) {
        guard activeMenu == nil, store.nodes.contains(where: { $0.id == id && $0.isFolder }) else { return }
        let menu = folderMenu(id)
        activeMenu = menu
        let bottom = button.isFlipped ? button.bounds.maxY + 4 : button.bounds.minY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bottom), in: button)
        activeMenu = nil
    }

    private func folderMenu(_ parent: UUID) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for node in store.children(of: parent) {
            let item = NSMenuItem(title: node.title, action: #selector(openItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = node.id
            item.image = NSImage(systemSymbolName: node.isFolder ? "folder" : "bookmark", accessibilityDescription: nil)
            if node.isFolder { item.submenu = folderMenu(node.id) }
            menu.addItem(item)
        }
        if menu.items.isEmpty {
            let empty = NSMenuItem(title: "Empty folder", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        return menu
    }

    private func contextMenu(for id: UUID) -> NSMenu {
        let menu = NSMenu()
        let manage = NSMenuItem(title: "Edit Favourites…", action: #selector(editItems), keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)
        let remove = NSMenuItem(title: "Remove", action: #selector(removeItem(_:)), keyEquivalent: "")
        remove.target = self
        remove.representedObject = id
        menu.addItem(remove)
        return menu
    }

    @objc private func openItem(_ sender: NSMenuItem) { if let id = sender.representedObject as? UUID { open(id) } }
    @objc private func editItems() { edit() }
    @objc private func removeItem(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { FavouriteRemoval.remove(id, from: store, undo: window?.undoManager) }
    }

    private func drop(_ id: UUID, at screenPoint: NSPoint, generation: UUID) -> FavouriteDropResult {
        guard generation == store.generation else { return .ignored }
        if screenRect.contains(screenPoint) {
            let point = strip.convert(window?.convertPoint(fromScreen: screenPoint) ?? .zero, from: nil)
            let target = strip.subviews.compactMap { $0 as? FavouriteButton }.first { $0.frame.maxX > point.x }
            if let target, target.isFolder, target.nodeID != id, abs(point.x - target.frame.midX) < target.frame.width / 4 {
                store.mutate(.move(id, parentId: target.nodeID, beforeId: nil))
            } else { store.mutate(.move(id, parentId: nil, beforeId: target?.nodeID)) }
            return .moved
        } else if !screenRect.insetBy(dx: -FavouriteButton.removalMargin, dy: -FavouriteButton.removalMargin)
            .contains(screenPoint) {
            FavouriteRemoval.remove(id, from: store, undo: window?.undoManager, puffAt: screenPoint)
            return .removed
        }
        return .ignored
    }
}

/// What a drop on or off the bar did, so the lifted item can land accordingly.
enum FavouriteDropResult {
    case moved, removed, ignored
}

final class FavouriteButton: NSButton {
    /// Points beyond the bar's edge at which dropping removes the favourite.
    static let removalMargin: CGFloat = 32

    var nodeID = UUID()
    var isFolder = false
    var activate: () -> Void = {}
    var finishDrag: (NSPoint, UUID) -> FavouriteDropResult = { _, _ in .ignored }
    var sourceGeneration: () -> UUID = { UUID() }
    var dragRect: () -> NSRect = { .zero }
    private var hover: DispatchWorkItem?
    private var tracking: NSTrackingArea?
    override func accessibilityPerformPress() -> Bool { activate(); return true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        guard isFolder, NSEvent.pressedMouseButtons == 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.window?.isKeyWindow == true, NSEvent.pressedMouseButtons == 0 else { return }
            self.activate()
        }
        hover?.cancel()
        hover = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    override func mouseExited(with event: NSEvent) { hover?.cancel() }
    override func viewWillMove(toWindow newWindow: NSWindow?) { super.viewWillMove(toWindow: newWindow); hover?.cancel() }
    override func keyDown(with event: NSEvent) {
        if [36, 49, 125].contains(event.keyCode) { activate() } else { super.keyDown(with: event) }
    }
    /// Tracks a press: a click opens the favourite, a drag lifts a copy of it
    /// that follows the pointer while the slot it left stays faintly visible.
    override func mouseDown(with event: NSEvent) {
        hover?.cancel()
        let generation = sourceGeneration()
        let start = event.locationInWindow
        let grab = convert(event.locationInWindow, from: nil)
        var ghost: FavouriteDragGhost?
        highlight(true)
        defer { highlight(false); alphaValue = 1; NSCursor.arrow.set() }
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) {
            if next.type == .keyDown {
                guard next.keyCode == 53 else { continue }
                ghost?.flyBack(to: screenFrame)
                return
            }
            let point = window?.convertPoint(toScreen: next.locationInWindow) ?? NSEvent.mouseLocation
            if ghost == nil, hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) > 5 {
                ghost = lift(grab: grab, at: point)
            }
            let removing = !dragRect().insetBy(dx: -Self.removalMargin, dy: -Self.removalMargin).contains(point)
            if next.type == .leftMouseUp {
                guard let ghost else {
                    activate()
                    return
                }
                switch finishDrag(point, generation) {
                case .removed: ghost.close()
                case .moved: ghost.fadeOut()
                case .ignored: ghost.flyBack(to: screenFrame)
                }
                return
            }
            guard let ghost else { continue }
            ghost.move(to: point, removing: removing)
            (removing ? NSCursor.disappearingItem : NSCursor.closedHand).set()
        }
    }

    private var screenFrame: NSRect {
        window?.convertToScreen(convert(bounds, to: nil)) ?? .zero
    }

    private func lift(grab: NSPoint, at point: NSPoint) -> FavouriteDragGhost {
        // Grab is measured from the bottom-left, whatever the view's flipping.
        let fromBottom = NSPoint(x: grab.x, y: isFlipped ? bounds.height - grab.y : grab.y)
        let ghost = FavouriteDragGhost(
            title: title,
            isFolder: isFolder,
            itemSize: bounds.size,
            grab: fromBottom,
            appearance: window?.effectiveAppearance
        )
        ghost.show(at: point)
        highlight(false)
        alphaValue = 0.25
        return ghost
    }
}
