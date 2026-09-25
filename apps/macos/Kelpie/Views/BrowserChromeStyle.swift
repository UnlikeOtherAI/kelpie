import AppKit
import SwiftUI

/// One adaptive palette for the browser chrome; web content keeps its own appearance.
enum BrowserChromeStyle {
    static let surfaceColor = color(light: 0xffffff, dark: 0x24262c)
    static let tabsColor = color(light: 0xe5eaf3, dark: 0x1b1d23)
    static let inkColor = color(light: 0x26334d, dark: 0xe3e8f2)
    static let surface = Color(nsColor: surfaceColor)
    static let tabs = Color(nsColor: tabsColor)
    static let ink = Color(nsColor: inkColor)
    static let muted = Color(nsColor: color(light: 0x78859d, dark: 0x9ca8bf))
    static let address = Color(nsColor: color(light: 0xf1f3f8, dark: 0x30343d))
    static let separator = Color(nsColor: color(light: 0xdde3ed, dark: 0x414652))

    private static func color(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                    srgbRed: CGFloat((value >> 16) & 255) / 255,
                    green: CGFloat((value >> 8
                ) & 255) / 255,
                           blue: CGFloat(value & 255) / 255,
                           alpha: 1)
        }
    }
}

/// Saved favourites use the same persistent records as bookmark management and the API.
struct FavouritesBarView: View {
    @ObservedObject var appearance: BrowserChromeAppearance
    let bookmarks: [BookmarkStore.Bookmark]
    let onNavigate: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(bookmarks) { bookmark in
                    HStack(spacing: 10) {
                        Image(systemName: "bookmark").font(.system(size: 15))
                        Text(bookmark.title.isEmpty ? bookmark.url : bookmark.title)
                            .font(.system(size: 12)).lineLimit(1)
                    }
                    .foregroundStyle(Color(nsColor: appearance.palette.foreground.color))
                    .frame(maxWidth: 220)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: 28)
                    .overlay(AppKitInvisibleButton(
                        accessibilityID: "browser.favourite.\(bookmark.id.uuidString)",
                        accessibilityLabel: bookmark.title.isEmpty ? bookmark.url : bookmark.title
                    ) { onNavigate(bookmark.url) })
                    .help(bookmark.url)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: BrowserChromeLayout.favouritesHeight)
    }
}

/// Keep the native underlap and the visible rows in agreement when bookmarks change.
enum BrowserChromeLayout {
    static let navigationHeight: CGFloat = 44
    static let favouritesHeight: CGFloat = 29

    static func underlap(collapsed: Bool, hasBookmarks: Bool) -> CGFloat {
        32 + (collapsed ? 0 : navigationHeight + (hasBookmarks ? favouritesHeight : 0))
    }
}

struct PageShareButton: NSViewRepresentable {
    let url: URL?
    var tintColor: NSColor?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ToolbarButtonView {
        let button = ToolbarButtonView(systemName: "square.and.arrow.up")
        button.setAccessibilityIdentifier("browser.action.share")
        button.setAccessibilityLabel("Share page")
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
        return button
    }

    func updateNSView(_ button: ToolbarButtonView, context: Context) {
        context.coordinator.url = url
        button.isEnabled = url != nil
        button.chromeTintColor = tintColor
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ToolbarButtonView, context: Context) -> CGSize? {
        CGSize(width: 32, height: 34)
    }

    final class Coordinator: NSObject {
        var url: URL?
        @objc func share(_ sender: NSButton) {
            guard let url else { return }
            NSSharingServicePicker(items: [url]).show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
