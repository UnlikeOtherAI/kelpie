import SwiftUI
import AppKit

/// One start page card: a 16:10 screenshot with the site's favicon in its
/// bottom-left corner and the domain underneath. A site without a screenshot
/// yet shows a two-tone tile with its favicon or initial. Mirrors `.site` in
/// the desktop page's `start.css`.
struct SiteCard: View {
    let site: StartPageSite
    let compact: Bool
    let order: Int
    let onTap: () -> Void

    @ObservedObject private var previews = SitePreviewCache.shared
    @ObservedObject private var favicons = FaviconCache.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                shot
                Text(site.domain)
                    .font(.system(size: compact ? 12 : 13, weight: .medium))
                    .foregroundStyle(isHovered ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(site.title.isEmpty ? site.url : site.title)
        .accessibilityLabel(site.title.isEmpty ? site.domain : site.title)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8)) { isHovered = hovering }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 10)
        .onAppear {
            favicons.image(forHost: site.host)
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.85).delay(Double(min(order, 24)) * 0.028)) {
                    appeared = true
                }
            }
        }
    }

    private var corner: CGFloat { 14 }

    private var shot: some View {
        let preview = previews.image(forHost: site.host)
        return ZStack(alignment: .bottomLeading) {
            if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1, anchor: .top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                badge
                    .padding(compact ? 8 : 10)
            } else {
                placeholder
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.24 : 0.12), radius: isHovered ? 18 : 9, y: isHovered ? 12 : 5)
        .offset(y: isHovered && !reduceMotion ? -4 : 0)
    }

    /// The favicon in a small white tile, or the initial on the site's tone.
    private var badge: some View {
        let size: CGFloat = compact ? 26 : 30
        let favicon = favicons.cachedImage(forHost: site.host)
        return ZStack {
            if let favicon {
                RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
                    .fill(.regularMaterial)
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: compact ? 16 : 18, height: compact ? 16 : 18)
            } else {
                RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
                    .fill(SiteTone.tone(for: site.host).dark)
                Text(initial)
                    .font(.system(size: compact ? 12 : 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
    }

    private var placeholder: some View {
        let tone = SiteTone.tone(for: site.host)
        let favicon = favicons.cachedImage(forHost: site.host)
        return ZStack {
            LinearGradient(colors: [tone.light, tone.dark], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let favicon {
                RoundedRectangle(cornerRadius: compact ? 13 : 16, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: compact ? 46 : 56, height: compact ? 46 : 56)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    .overlay(
                        Image(nsImage: favicon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: compact ? 24 : 30, height: compact ? 24 : 30)
                    )
                    .scaleEffect(isHovered && !reduceMotion ? 1.08 : 1)
            } else {
                Text(initial)
                    .font(.system(size: compact ? 32 : 40, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                    .scaleEffect(isHovered && !reduceMotion ? 1.08 : 1)
            }
        }
    }

    private var initial: String {
        site.domain.first.map { String($0).uppercased() } ?? "?"
    }
}
