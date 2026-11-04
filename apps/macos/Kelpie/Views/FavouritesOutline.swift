import AppKit
import SwiftUI

struct FavouritesOutline: NSViewRepresentable {
    @ObservedObject var store: BookmarkStore
    @Binding var selection: UUID?
    let onNavigate: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Favourites"
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 30
        outline.indentationPerLevel = 18
        outline.style = .sourceList
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.openSelection(_:))
        outline.registerForDraggedTypes([Coordinator.pasteboardType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setAccessibilityIdentifier("browser.favourites.tree")
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        context.coordinator.outline = outline
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reload()
    }

    final class Item: NSObject {
        let id: UUID
        init(_ id: UUID) { self.id = id }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        static let pasteboardType = NSPasteboard.PasteboardType("com.kelpie.favourite")
        var parent: FavouritesOutline
        weak var outline: NSOutlineView?
        private var items: [UUID: Item] = [:]
        private var snapshot: [BookmarkStore.Bookmark] = []
        private var generation = UUID()
        private var dragGeneration: UUID?
        init(_ parent: FavouritesOutline) { self.parent = parent }

        func reload() {
            guard let outline, snapshot != parent.store.nodes || generation != parent.store.generation else { return }
            let expanded = items.values.filter { outline.isItemExpanded($0) }.map(\.id)
            if generation != parent.store.generation { items = [:] }
            generation = parent.store.generation
            snapshot = parent.store.nodes
            items = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, items[$0.id] ?? Item($0.id)) })
            outline.reloadData()
            for id in expanded { if let item = items[id] { outline.expandItem(item) } }
            if let id = parent.selection, let item = items[id] {
                let row = outline.row(forItem: item)
                if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            }
        }
        private func children(_ item: Any?) -> [BookmarkStore.Bookmark] { parent.store.children(of: (item as? Item)?.id) }
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { children(item).count }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            let node = children(item)[index]
            return items[node.id] ?? Item(node.id)
        }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            parent.store.nodes.first { $0.id == (item as? Item)?.id }?.isFolder == true
        }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = parent.store.nodes.first(where: { $0.id == (item as? Item)?.id }) else { return nil }
            let row = NSTableCellView()
            let label = NSTextField(labelWithString: node.title)
            label.lineBreakMode = .byTruncatingTail
            let icon = NSImageView(image: NSImage(systemSymbolName: node.isFolder ? "folder" : "bookmark", accessibilityDescription: nil) ?? NSImage())
            row.addSubview(icon)
            row.addSubview(label)
            icon.frame = NSRect(x: 2, y: 7, width: 16, height: 16)
            label.frame = NSRect(x: 26, y: 6, width: 280, height: 20)
            label.autoresizingMask = [.width]
            row.textField = label
            row.imageView = icon
            row.setAccessibilityLabel(node.title)
            row.setAccessibilityIdentifier("browser.favourites.row.\(node.id.uuidString)")
            return row
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outline else { return }
            parent.selection = (outline.item(atRow: outline.selectedRow) as? Item)?.id
        }
        @objc func openSelection(_ sender: NSOutlineView) {
            guard let id = (sender.item(atRow: sender.clickedRow) as? Item)?.id,
                  let node = parent.store.nodes.first(where: { $0.id == id }) else { return }
            if node.isFolder {
                if sender.isItemExpanded(items[id]) { sender.collapseItem(items[id]) } else { sender.expandItem(items[id]) }
            } else { parent.onNavigate(node.url) }
        }
        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let item = item as? Item else { return nil }
            dragGeneration = parent.store.generation
            let value = NSPasteboardItem()
            value.setString(item.id.uuidString, forType: Self.pasteboardType)
            return value
        }
        private func mutation(_ info: NSDraggingInfo, item: Any?, index: Int) -> BookmarkTree.Mutation? {
            guard dragGeneration == parent.store.generation,
                  let raw = info.draggingPasteboard.string(forType: Self.pasteboardType), let id = UUID(uuidString: raw) else { return nil }
            let destination = (item as? Item)?.id
            let siblings = parent.store.children(of: destination)
            let before = index >= 0 && index < siblings.count ? siblings[index].id : nil
            return .move(id, parentId: destination, beforeId: before)
        }
        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            guard let change = mutation(info, item: item, index: index), (try? change.apply(to: parent.store.nodes)) != nil else { return [] }
            return .move
        }
        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            guard let change = mutation(info, item: item, index: index) else { return false }
            parent.store.mutate(change)
            return true
        }
    }
}
