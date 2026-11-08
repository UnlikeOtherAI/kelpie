import SwiftUI

struct BrowserLinkStatusBar: View {
    @ObservedObject var appearance: BrowserChromeAppearance
    let url: String

    var body: some View {
        HStack {
            Text(url)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: appearance.palette.foreground.color))
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel("Link destination")
                .accessibilityIdentifier("browser.status.link")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 24)
        .background(BrowserGlassBackground(appearance: appearance))
    }
}
