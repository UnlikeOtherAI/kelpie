import SwiftUI

/// Native materials shared by the address field and circular toolbar controls.
struct BrowserGlass: ViewModifier {
    var capsule = true

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: capsule ? 28 : 16))
            .overlay {
                RoundedRectangle(cornerRadius: capsule ? 28 : 16)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

struct BrowserChromeButton: View {
    let symbol: String
    let label: String
    let identifier: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .frame(width: 44, height: 44)
                .modifier(BrowserGlass())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

func browserDomain(_ value: String) -> String {
    guard let host = URL(string: value)?.host else { return "Start Page" }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}

struct BrowserTabLabel: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tab.isStartPage ? "star.fill" : "globe")
                .font(.system(size: 17))
            Text(tab.isStartPage ? "Start Page" : (tab.pageTitle.isEmpty ? browserDomain(tab.currentURL) : tab.pageTitle))
                .font(.subheadline)
                .lineLimit(1)
        }
    }
}
