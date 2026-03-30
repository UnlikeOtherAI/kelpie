import SwiftUI

/// Full-screen bookmarks list. Tap a bookmark to navigate.
struct BookmarksView: View {
    @ObservedObject var store = BookmarkStore.shared
    let onNavigate: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.bookmarks.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "bookmark")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Bookmarks")
                            .font(.headline)
                        Text("Add bookmarks via the CLI or MCP.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(store.bookmarks) { bookmark in
                            Button {
                                onNavigate(bookmark.url)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bookmark.title)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(bookmark.url)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                store.remove(id: store.bookmarks[i].id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                if !store.bookmarks.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear All", role: .destructive) { store.removeAll() }
                    }
                }
            }
        }
    }
}
