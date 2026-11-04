import SwiftUI
import UniformTypeIdentifiers

struct BookmarksView: View {
    @ObservedObject var store = BookmarkStore.shared
    let currentTitle: String
    let currentURL: String
    let onNavigate: (String) -> Void
    let onDismiss: () -> Void
    var closeOnNavigate = true
    @State private var expanded = Set<UUID>()
    @State private var editing: BookmarkStore.Bookmark?
    @State private var moving: BookmarkStore.Bookmark?
    @State private var removing: BookmarkStore.Bookmark?
    @State private var drag: String?
    private var canAddPage: Bool {
        (try? BookmarkTree.validate(.init(title: currentTitle.isEmpty ? currentURL : currentTitle, url: currentURL))) != nil
    }

    private var rows: [(node: BookmarkStore.Bookmark, depth: Int)] {
        var result: [(BookmarkStore.Bookmark, Int)] = []
        var pending = store.children(of: nil).reversed().map { ($0, 0) }
        while let (node, depth) = pending.popLast() {
            result.append((node, depth))
            if expanded.contains(node.id) { pending += store.children(of: node.id).reversed().map { ($0, depth + 1) } }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Top Level").font(.subheadline).frame(maxWidth: .infinity).padding(10)
                    .background(.quaternary)
                    .onDrop(of: [.plainText], delegate: FavouriteDrop(store: store, target: nil, drag: $drag))
                    .accessibilityIdentifier("browser.bookmarks.root")
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if store.nodes.isEmpty { Text("No favourites yet. Add a page or create a folder.").foregroundStyle(.secondary).padding() }
                        ForEach(rows, id: \.node.id) { row in
                            favouriteRow(row.node, depth: row.depth).padding(.horizontal, 16).padding(.vertical, 8)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                if let error = store.syncError { Text(error).font(.caption).foregroundStyle(.red).padding(8) }
                if store.isSyncing { ProgressView("Saving favourites…").padding(8) }
                if store.canUndoRemoval {
                    Button("Undo Remove") { Task { try? await store.undoLastRemoval() } }
                        .padding(10).accessibilityIdentifier("browser.bookmarks.undo")
                }
            }
            .navigationTitle("Favourites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done", action: onDismiss).accessibilityIdentifier("browser.bookmarks.done") }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Folder") { editing = BookmarkStore.Bookmark(title: "New Folder", kind: .folder) }
                        Button("Add Current Page") { store.add(title: currentTitle, url: currentURL) }
                            .disabled(!canAddPage)
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add favourite or folder").accessibilityIdentifier("browser.bookmarks.add")
                }
            }
        }
        .sheet(item: $editing) { node in FavouriteEditSheet(node: node, store: store) }
        .sheet(item: $moving) { node in FavouriteMoveSheet(node: node, store: store) }
        .confirmationDialog("Remove this favourite?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let removing {
                Button("Remove", role: .destructive) { Task { try? await store.removeWithUndo(id: removing.id) }; self.removing = nil }
            }
        } message: {
            if let removing, removing.isFolder { Text("This removes the folder and everything inside it. You can undo it.") }
        }
        .onChange(of: store.generation) { _ in editing = nil; moving = nil; removing = nil; drag = nil; expanded = [] }
    }

    private func favouriteRow(_ node: BookmarkStore.Bookmark, depth: Int) -> some View {
        HStack(spacing: 10) {
            Button {
                if node.isFolder {
                    if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
                } else {
                    onNavigate(node.url)
                    if closeOnNavigate { onDismiss() }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: node.isFolder ? (expanded.contains(node.id) ? "chevron.down" : "chevron.right") : "bookmark").frame(width: 16)
                    if node.isFolder { Image(systemName: "folder") }
                    VStack(alignment: .leading) {
                        Text(node.title).foregroundStyle(.primary)
                        if !node.isFolder { Text(node.url).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("browser.bookmarks.row.\(node.id.uuidString)")
            Menu {
                Button("Edit") { editing = node }
                Button("Move…") { moving = node }
                if node.isFolder {
                    Button("New Folder Inside") { editing = BookmarkStore.Bookmark(title: "New Folder", kind: .folder, parentId: node.id) }
                    Button("Add Current Page Here") { store.add(title: currentTitle, url: currentURL, parentId: node.id) }
                        .disabled(!canAddPage)
                }
                Button("Remove", role: .destructive) { removing = node }
            } label: { Image(systemName: "ellipsis").padding(8) }
            .accessibilityLabel("Actions for \(node.title)")
            .accessibilityIdentifier("browser.bookmarks.actions.\(node.id.uuidString)")
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).padding(8)
                .accessibilityLabel("Drag \(node.title)")
                .accessibilityIdentifier("browser.bookmarks.drag.\(node.id.uuidString)")
                .onDrag {
                    let payload = "kelpie:\(store.generation.uuidString):\(node.id.uuidString)"
                    drag = payload
                    return NSItemProvider(object: payload as NSString)
                }
        }
        .padding(.leading, CGFloat(min(depth, 8)) * 16)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .onDrop(of: [.plainText], delegate: FavouriteDrop(store: store, target: node, drag: $drag))
    }
}

private struct FavouriteDrop: DropDelegate {
    let store: BookmarkStore
    let target: BookmarkStore.Bookmark?
    @Binding var drag: String?
    func validateDrop(info: DropInfo) -> Bool { drag != nil && info.hasItemsConforming(to: [.plainText]) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let expected = drag, let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let generation = store.generation
        let parent: UUID?
        let before: UUID?
        if let target {
            if target.isFolder && info.location.y >= 12 && info.location.y <= 36 { parent = target.id; before = nil } else {
                parent = target.parentId
                let siblings = store.children(of: parent)
                let index = siblings.firstIndex { $0.id == target.id } ?? 0
                before = info.location.y < 24 ? target.id : siblings.dropFirst(index + 1).first?.id
            }
        } else { parent = nil; before = nil }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String, raw == expected,
                  let id = UUID(uuidString: String(raw.split(separator: ":").last ?? "")) else { return }
            Task { @MainActor in
                guard store.generation == generation, raw.hasPrefix("kelpie:\(generation.uuidString):") else { return }
                store.mutate(.move(id, parentId: parent, beforeId: before))
                drag = nil
            }
        }
        return true
    }
}

private struct FavouriteEditSheet: View {
    let node: BookmarkStore.Bookmark
    @ObservedObject var store: BookmarkStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var url = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $title).accessibilityIdentifier("browser.bookmarks.name")
                if !node.isFolder { TextField("URL", text: $url).textInputAutocapitalization(.never).keyboardType(.URL).accessibilityIdentifier("browser.bookmarks.url") }
                if let error = store.syncError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(node.isFolder ? "Edit Folder" : "Edit Favourite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let mutation: BookmarkTree.Mutation
                            if store.nodes.contains(where: { $0.id == node.id }) {
                                mutation = .update(node.id, title: title, url: node.isFolder ? nil : url)
                            } else {
                                var added = node
                                added.title = title
                                added.url = node.isFolder ? "" : url
                                mutation = .add(added)
                            }
                            do { try await store.mutate(mutation)?.value; dismiss() } catch { }
                        }
                    }.accessibilityIdentifier("browser.bookmarks.save")
                }
            }
        }.onAppear { title = node.title; url = node.url }
    }
}

private struct FavouriteMoveSheet: View {
    let node: BookmarkStore.Bookmark
    @ObservedObject var store: BookmarkStore
    @Environment(\.dismiss) private var dismiss
    @State private var parent: UUID?
    @State private var before: UUID?
    private var excluded: Set<UUID> { Set(BookmarkTree.subtree(node.id, in: store.nodes).map(\.id)) }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Folder", selection: $parent) {
                    Text("Top Level").tag(nil as UUID?)
                    ForEach(store.nodes.filter { $0.isFolder && !excluded.contains($0.id) }) { folder in Text(folder.title).tag(Optional(folder.id)) }
                }
                Picker("Position", selection: $before) {
                    Text("At the End").tag(nil as UUID?)
                    ForEach(store.children(of: parent).filter { $0.id != node.id }) { sibling in Text("Before \(sibling.title)").tag(Optional(sibling.id)) }
                }
                if let error = store.syncError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Move Favourite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { Task { do { try await store.mutate(.move(node.id, parentId: parent, beforeId: before))?.value; dismiss() } catch { } } }
                }
            }
        }.onAppear { parent = node.parentId }.onChange(of: parent) { _ in before = nil }
    }
}
