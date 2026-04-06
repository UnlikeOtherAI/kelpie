import SwiftUI
import AppKit

struct StartPageView: View {
    @ObservedObject var bookmarkStore: BookmarkStore
    @ObservedObject var historyStore: HistoryStore
    let onNavigate: (String) -> Void

    private var iconBackgroundColor: Color {
        guard let img = NSImage(named: "WelcomeIcon"),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pixel = rep.colorAt(x: 0, y: 0) else {
            return Color(red: 232 / 255, green: 241 / 255, blue: 249 / 255)
        }
        return Color(nsColor: pixel)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 36) {
                // App icon header
                HStack {
                    Spacer()
                    if let img = NSImage(named: "WelcomeIcon") {
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    }
                    Spacer()
                }
                .padding(.top, 40)

                if !bookmarkStore.bookmarks.isEmpty {
                    StartPageSection(title: "Favourites") {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 72, maximum: 96))],
                            alignment: .leading,
                            spacing: 16
                        ) {
                            ForEach(bookmarkStore.bookmarks) { bm in
                                BookmarkTileView(bookmark: bm) { onNavigate(bm.url) }
                            }
                        }
                    }
                }

                let recent = Array(historyStore.entries.prefix(20))
                if !recent.isEmpty {
                    StartPageSection(title: "Recent") {
                        VStack(spacing: 0) {
                            ForEach(recent) { entry in
                                HistoryRowView(
                                    entry: entry,
                                    onTap: { onNavigate(entry.url) },
                                    onRemove: { historyStore.remove(id: entry.id) }
                                )
                                if entry.id != recent.last?.id {
                                    Divider().opacity(0.15)
                                }
                            }
                        }
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                if bookmarkStore.bookmarks.isEmpty && historyStore.entries.isEmpty {
                    Spacer(minLength: 100)
                    Text("Open a website to get started")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.vertical, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                iconBackgroundColor
                if let img = NSImage(named: "WelcomeIcon") {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .opacity(0.30)
                }
            }
            .clipped()
        }
    }
}

// MARK: - Section wrapper

private struct StartPageSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            content()
        }
    }
}

// MARK: - Bookmark tile

private struct BookmarkTileView: View {
    let bookmark: BookmarkStore.Bookmark
    let onTap: () -> Void

    private var domainLetter: String {
        let host = URL(string: bookmark.url)?.host ?? bookmark.url
        return host.first.map { String($0).uppercased() } ?? "?"
    }

    private var tileColor: Color {
        let palette: [Color] = [
            Color(red: 0.40, green: 0.56, blue: 0.85),
            Color(red: 0.55, green: 0.75, blue: 0.55),
            Color(red: 0.85, green: 0.55, blue: 0.40),
            Color(red: 0.70, green: 0.50, blue: 0.85),
            Color(red: 0.85, green: 0.75, blue: 0.35),
            Color(red: 0.50, green: 0.75, blue: 0.80)
        ]
        let host = URL(string: bookmark.url)?.host ?? bookmark.url
        let hash = host.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(tileColor)
                        .frame(width: 56, height: 56)
                    Text(domainLetter)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(bookmark.title.isEmpty ? (URL(string: bookmark.url)?.host ?? bookmark.url) : bookmark.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 72)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History row

private struct HistoryRowView: View {
    let entry: HistoryStore.HistoryEntry
    let onTap: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    private var domainLetter: String {
        let host = URL(string: entry.url)?.host ?? entry.url
        return host.first.map { String($0).uppercased() } ?? "?"
    }

    private var letterColor: Color {
        let palette: [Color] = [
            Color(red: 0.40, green: 0.56, blue: 0.85),
            Color(red: 0.55, green: 0.75, blue: 0.55),
            Color(red: 0.85, green: 0.55, blue: 0.40),
            Color(red: 0.70, green: 0.50, blue: 0.85),
            Color(red: 0.85, green: 0.75, blue: 0.35),
            Color(red: 0.50, green: 0.75, blue: 0.80)
        ]
        let host = URL(string: entry.url)?.host ?? entry.url
        let hash = host.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon area: letter avatar or delete button on hover
            ZStack {
                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.secondary.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(letterColor)
                            .frame(width: 28, height: 28)
                        Text(domainLetter)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .frame(width: 28, height: 28)
            .animation(.easeOut(duration: 0.15), value: isHovered)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? entry.url : entry.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(entry.url)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
        .onTapGesture { onTap() }
        .background(isHovered ? Color.primary.opacity(0.04) : .clear)
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}
