import SwiftUI
import AppKit

/// macOS bookmarks sheet. Tap a bookmark to navigate.
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
        AppKitFirstMouseSheetContainer {
            NavigationStack {
                Group {
                    if store.bookmarks.isEmpty {
                        emptyState(
                            icon: "bookmark",
                            title: "No Bookmarks",
                            subtitle: "Use Add Current to save this page."
                        )
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
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("browser.bookmarks.row.\(bookmark.id.uuidString)")
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                .listRowBackground(Color.clear)
                                .contextMenu {
                                    Button("Remove", role: .destructive) {
                                        store.remove(id: bookmark.id)
                                    }
                                }
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    store.remove(id: store.bookmarks[index].id)
                                }
                            }
                        }
                        .listStyle(.inset)
                    }
                }
                .navigationTitle("Bookmarks")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("browser.bookmarks.done")
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if !store.bookmarks.isEmpty {
                            Button("Clear All", role: .destructive) {
                                store.removeAll()
                            }
                            .accessibilityIdentifier("browser.bookmarks.clear-all")
                        }
                        if !currentURL.isEmpty && !isCurrentPageBookmarked {
                            Button("Add Current") {
                                let title = currentTitle.isEmpty ? currentURL : currentTitle
                                store.add(title: title, url: currentURL)
                            }
                            .accessibilityIdentifier("browser.bookmarks.add-current")
                        }
                    }
                }
            }
            .frame(minWidth: 520, minHeight: 420)
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
