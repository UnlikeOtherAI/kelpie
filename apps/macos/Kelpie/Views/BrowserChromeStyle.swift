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

/// Illustrative favourites requested for the reference design. Never persisted as user bookmarks.
struct FavouritesBarView: View {
    @ObservedObject var appearance: BrowserChromeAppearance
    let onNavigate: (String) -> Void
    let onAddBookmark: () -> Void
    let canAddBookmark: Bool

    private struct Favourite: Identifiable {
        let title: String
        let icon: String
        let color: Color
        let url: String
        var id: String { title }
    }

    private let favourites: [Favourite] = [
        .init(title: "Personal", icon: "folder", color: BrowserChromeStyle.ink, url: "https://www.icloud.com"),
        .init(title: "Work", icon: "folder", color: BrowserChromeStyle.ink, url: "https://github.com"),
        .init(title: "Projects", icon: "square.grid.2x2.fill", color: .blue, url: "https://github.com"),
        .init(title: "Inspiration", icon: "leaf.fill", color: .green, url: "https://www.pinterest.com"),
        .init(title: "Travel", icon: "mappin", color: .red, url: "https://maps.google.com"),
        .init(title: "Recipes", icon: "cup.and.saucer.fill", color: .orange, url: "https://www.bbcgoodfood.com"),
        .init(title: "Reading", icon: "book.fill", color: .purple, url: "https://en.wikipedia.org")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(favourites) { favourite in
                    label(favourite.title, icon: favourite.icon, color: favourite.icon == "folder" ? Color(nsColor: appearance.palette.foreground.color) : favourite.color)
                        .overlay(AppKitInvisibleButton(
                    accessibilityID: "browser.favourite.\(favourite.id)",
                    accessibilityLabel: favourite.title
                ) { onNavigate(favourite.url) })
                }
                label("Add bookmark…", icon: "plus", color: Color(nsColor: appearance.palette.foreground.color.withAlphaComponent(0.7)))
                    .overlay(AppKitInvisibleButton(
                    accessibilityID: "browser.favourite.add",
                    accessibilityLabel: "Add bookmark",
                    isEnabled: canAddBookmark,
                    action: onAddBookmark
                ))
                    .opacity(canAddBookmark ? 1 : 0.5)
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 29)
    }

    private func label(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(color)
            Text(title).font(.system(size: 12)).foregroundStyle(Color(nsColor: appearance.palette.foreground.color))
        }
        .fixedSize()
        .frame(height: 28)
        .contentShape(Rectangle())
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
