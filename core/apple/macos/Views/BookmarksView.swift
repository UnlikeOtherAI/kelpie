import SwiftUI
import AppKit

struct BookmarksView: View {
    @ObservedObject var store = BookmarkStore.shared
    let currentTitle: String
    let currentURL: String
    let onNavigate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?
    @State private var title = ""
    @State private var url = ""
    private var selected: BookmarkStore.Bookmark? { store.nodes.first { $0.id == selection } }
    private var destination: UUID? { selected?.isFolder == true ? selection : selected?.parentId }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Edit Favourites").font(.title2.bold())
                Spacer()
                action("Done", id: "done") { dismiss() }
            }
            HStack(spacing: 10) {
                action("New Folder", id: "new-folder") {
                    let folder = BookmarkStore.Bookmark(title: "New Folder", kind: .folder, parentId: destination)
                    store.mutate(.add(folder))
                    selection = folder.id
                }
                action("Add Current Page", id: "add-current", enabled: URL(string: currentURL)?.host != nil) {
                    store.add(title: currentTitle, url: currentURL, parentId: destination)
                }
                Spacer()
                action("Undo Remove", id: "undo", enabled: store.canUndoRemoval) { Task { try? await store.undoLastRemoval() } }
            }
            Text("Drag to reorder. Drop on a folder to move inside it, or between root items to move out.")
                .font(.caption).foregroundStyle(.secondary)
            FavouritesOutline(store: store, selection: $selection) { onNavigate($0); dismiss() }.frame(minHeight: 240)
            if let selected {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow { Text("Name"); TextField("Name", text: $title).accessibilityIdentifier("browser.bookmarks.name") }
                    if !selected.isFolder {
                        GridRow { Text("URL"); TextField("https://", text: $url).accessibilityIdentifier("browser.bookmarks.url") }
                    }
                }
                HStack {
                    action("Save", id: "save") { store.mutate(.update(selected.id, title: title, url: selected.isFolder ? nil : url)) }
                    action("Move to Top Level", id: "move-root", enabled: selected.parentId != nil) {
                        store.mutate(.move(selected.id, parentId: nil, beforeId: nil))
                    }
                    Spacer()
                    action("Remove", id: "remove") { FavouriteRemoval.remove(selected.id, from: store, undo: nil) }
                }
            }
            if let error = store.syncError { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if store.isSyncing { ProgressView("Saving favourites…").controlSize(.small) }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 480)
        .onChange(of: selection) { _, _ in title = selected?.title ?? ""; url = selected?.url ?? "" }
        .onChange(of: store.generation) { _, _ in selection = nil }
    }

    private func action(_ title: String, id: String, enabled: Bool = true, run: @escaping () -> Void) -> some View {
        Text(title).padding(.horizontal, 10).padding(.vertical, 7)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .opacity(enabled ? 1 : 0.4)
            .overlay(AppKitInvisibleButton(accessibilityID: "browser.bookmarks.\(id)", accessibilityLabel: title, isEnabled: enabled, action: run))
    }
}
