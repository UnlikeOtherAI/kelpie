import SwiftUI

/// A transient, non-interactive destination preview that never changes the page viewport.
struct BrowserLinkPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let url: String

    var body: some View {
        GeometryReader { geometry in
            if !url.isEmpty {
                Text(verbatim: url)
                    .font(.system(size: 11))
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color(red: 0.16, green: 0.22, blue: 0.31))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        colorScheme == .dark ? Color(red: 0.16, green: 0.22, blue: 0.31) : Color(red: 0.84, green: 0.90, blue: 0.98),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .accessibilityLabel("Link destination")
                    .accessibilityValue(url)
                    .accessibilityIdentifier("browser.status.link")
                    .frame(maxWidth: min(640, max(0, geometry.size.width - 12)), alignment: .leading)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: url.isEmpty)
        .allowsHitTesting(false)
    }
}
