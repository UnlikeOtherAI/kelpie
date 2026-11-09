import SwiftUI
import AppKit

/// The page a new tab opens on: the favourites and the most recently visited
/// sites as screenshot cards, each with its favicon in the corner and its
/// domain underneath.
///
/// The Windows and Linux start page (`core/native/engine-chromium-desktop/
/// resources/start_page`) mirrors this layout, its measurements and its colours.
struct StartPageView: View {
    @ObservedObject var bookmarkStore: BookmarkStore
    @ObservedObject var historyStore: HistoryStore
    @ObservedObject private var previews = SitePreviewCache.shared
    let onNavigate: (String) -> Void

    /// Mirrors `start_page::kRecentSiteLimit`.
    private static let recentLimit = 8

    private var favourites: [StartPageSite] {
        bookmarkStore.bookmarks.compactMap { StartPageSite(url: $0.url, title: $0.title) }
    }

    /// The latest visit to each site, newest first, leaving out sites that are
    /// already favourites.
    private var recent: [StartPageSite] {
        var shown = Set(favourites.map(\.host))
        var sites: [StartPageSite] = []
        for entry in historyStore.entries {
            guard sites.count < Self.recentLimit, let site = StartPageSite(url: entry.url, title: entry.title),
                  shown.insert(site.host).inserted else { continue }
            sites.append(site)
        }
        return sites
    }

    var body: some View {
        let favourites = favourites
        let recent = recent
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 44) {
                HStack {
                    Spacer()
                    if let icon = KelpieResources.bundle.image(forResource: "WelcomeIcon") {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .shadow(color: .black.opacity(0.22), radius: 9, y: 6)
                    }
                    Spacer()
                }

                if !favourites.isEmpty {
                    StartPageSection(title: "Favourites") {
                        SiteGrid(sites: favourites, compact: false, firstOrder: 0, onNavigate: onNavigate)
                    }
                }

                if !recent.isEmpty {
                    StartPageSection(title: "Recent") {
                        SiteGrid(sites: recent, compact: true, firstOrder: favourites.count, onNavigate: onNavigate)
                    }
                }

                if favourites.isEmpty && recent.isEmpty {
                    Text("Open a website to get started")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                }
            }
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { StartPageBackground() }
    }
}

/// One card's worth of data.
struct StartPageSite: Identifiable {
    let url: String
    let title: String
    let host: String

    var id: String { url }

    /// The caption: the host without a leading `www.`.
    var domain: String { host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }

    init?(url: String, title: String) {
        guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
              let host = parsed.host?.lowercased(), !host.isEmpty else { return nil }
        self.url = url
        self.title = title
        self.host = host
    }
}

/// Tile tones for sites without a screenshot: the six start page colours,
/// lightened and darkened, picked by the sum of the host's Unicode scalars.
/// Mirrors `.tone-0` … `.tone-5` in the desktop page's `start.css`.
enum SiteTone {
    private static let tones: [(light: Color, dark: Color)] = [
        (Color(red: 133 / 255, green: 170 / 255, blue: 235 / 255), Color(red: 77 / 255, green: 113 / 255, blue: 189 / 255)),
        (Color(red: 164 / 255, green: 212 / 255, blue: 164 / 255), Color(red: 105 / 255, green: 163 / 255, blue: 113 / 255)),
        (Color(red: 240 / 255, green: 168 / 255, blue: 132 / 255), Color(red: 196 / 255, green: 111 / 255, blue: 78 / 255)),
        (Color(red: 199 / 255, green: 158 / 255, blue: 235 / 255), Color(red: 146 / 255, green: 98 / 255, blue: 191 / 255)),
        (Color(red: 240 / 255, green: 214 / 255, blue: 118 / 255), Color(red: 196 / 255, green: 160 / 255, blue: 60 / 255)),
        (Color(red: 155 / 255, green: 211 / 255, blue: 222 / 255), Color(red: 92 / 255, green: 160 / 255, blue: 176 / 255))
    ]

    static func tone(for host: String) -> (light: Color, dark: Color) {
        let hash = host.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return tones[abs(hash) % tones.count]
    }
}

// MARK: - Layout

private struct StartPageSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.96)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            content()
        }
    }
}

private struct SiteGrid: View {
    let sites: [StartPageSite]
    let compact: Bool
    let firstOrder: Int
    let onNavigate: (String) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: compact ? 148 : 184), spacing: compact ? 18 : 22, alignment: .top)],
            alignment: .leading,
            spacing: compact ? 22 : 26
        ) {
            ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                SiteCard(site: site, compact: compact, order: firstOrder + index) { onNavigate(site.url) }
            }
        }
    }
}

/// Two soft glows in the app icon's mint and blue behind the content, as on the
/// desktop page.
private struct StartPageBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                glows(in: proxy.size)
                    .opacity(colorScheme == .dark ? 0.32 : 0.5)
            }
        }
        .ignoresSafeArea()
    }

    private func glow(_ color: Color) -> RadialGradient {
        RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: 220)
    }

    private func glows(in size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(glow(Color(red: 46 / 255, green: 230 / 255, blue: 176 / 255).opacity(0.75)))
                .frame(width: 640, height: 640)
                .blur(radius: 80)
                .position(x: size.width / 2 - 280, y: 160)
            Circle()
                .fill(glow(Color(red: 26 / 255, green: 156 / 255, blue: 1).opacity(0.6)))
                .frame(width: 640, height: 640)
                .blur(radius: 80)
                .position(x: size.width / 2 + 280, y: 120)
        }
    }
}
