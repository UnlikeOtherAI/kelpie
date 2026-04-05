import SwiftUI

/// Full-screen bookmarks list. Tap a bookmark to navigate.
struct BookmarksView: View {
    @ObservedObject var store = BookmarkStore.shared
    let currentTitle: String
    let currentURL: String
    let onNavigate: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var isCurrentPageBookmarked: Bool {
        store.bookmarks.contains { $0.url == currentURL }
    }

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
                        Text("Tap + to bookmark this page.")
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
                            .accessibilityIdentifier("browser.bookmarks.row.\(bookmark.id.uuidString)")
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
                        .accessibilityIdentifier("browser.bookmarks.done")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if !store.bookmarks.isEmpty {
                            Button("Clear All", role: .destructive) { store.removeAll() }
                                .accessibilityIdentifier("browser.bookmarks.clear-all")
                        }
                        if !currentURL.isEmpty {
                            Button {
                                if isCurrentPageBookmarked {
                                    if let bookmark = store.bookmarks.first(where: { $0.url == currentURL }) {
                                        store.remove(id: bookmark.id)
                                    }
                                } else {
                                    let title = currentTitle.isEmpty ? currentURL : currentTitle
                                    store.add(title: title, url: currentURL)
                                }
                            } label: {
                                Image(systemName: isCurrentPageBookmarked ? "bookmark.fill" : "plus")
                            }
                            .accessibilityIdentifier("browser.bookmarks.toggle-current")
                        }
                    }
                }
            }
        }
    }
}
