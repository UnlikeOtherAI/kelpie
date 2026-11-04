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
                button.finishDrag = { [weak self] point, generation in self?.drop(node.id, at: point, generation: generation) }
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
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: button)
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

    private func drop(_ id: UUID, at screenPoint: NSPoint, generation: UUID) {
        guard generation == store.generation else { return }
        if screenRect.contains(screenPoint) {
            let point = stack.convert(window?.convertPoint(fromScreen: screenPoint) ?? .zero, from: nil)
            let target = strip.subviews.compactMap { $0 as? FavouriteButton }.first { $0.frame.maxX > point.x }
            if let target, target.isFolder, target.nodeID != id, abs(point.x - target.frame.midX) < target.frame.width / 4 {
                store.mutate(.move(id, parentId: target.nodeID, beforeId: nil))
            } else { store.mutate(.move(id, parentId: nil, beforeId: target?.nodeID)) }
        } else if !screenRect.insetBy(dx: -32, dy: -32).contains(screenPoint) {
            FavouriteRemoval.remove(id, from: store, undo: window?.undoManager, puffAt: screenPoint)
        }
    }
}

final class FavouriteButton: NSButton {
    var nodeID = UUID()
    var isFolder = false
    var activate: () -> Void = {}
    var finishDrag: (NSPoint, UUID) -> Void = { _, _ in }
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
    override func mouseDown(with event: NSEvent) {
        hover?.cancel()
        let generation = sourceGeneration()
        let start = event.locationInWindow
        var dragged = false
        highlight(true)
        defer { highlight(false); alphaValue = 1; NSCursor.arrow.set() }
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) {
            if next.type == .keyDown { if next.keyCode == 53 { return }; continue }
            let distance = hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y)
            dragged = dragged || distance > 5
            let point = window?.convertPoint(toScreen: next.locationInWindow) ?? NSEvent.mouseLocation
            if next.type == .leftMouseUp {
                if dragged { finishDrag(point, generation) } else { activate() }
                return
            }
            if dragged {
                alphaValue = 0.45
                if dragRect().insetBy(dx: -32, dy: -32).contains(point) { NSCursor.closedHand.set() } else { NSCursor.disappearingItem.set() }
            }
        }
    }
}
