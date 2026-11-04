import SwiftUI

/// Window width, not browser viewport emulation or device model, chooses the surface.
struct FavouritesPresentation: View {
    let currentTitle: String
    let currentURL: String
    let onNavigate: (String) -> Void
    let onDismiss: () -> Void
    var body: some View {
        GeometryReader { geometry in
            let drawer = geometry.size.width >= 600
            ZStack(alignment: .leading) {
                Color.black.opacity(drawer ? 0.25 : 0).ignoresSafeArea().onTapGesture(perform: onDismiss)
                BookmarksView(
                    currentTitle: currentTitle,
                    currentURL: currentURL,
                    onNavigate: onNavigate,
                    onDismiss: onDismiss,
                    closeOnNavigate: !drawer
                )
                    .frame(width: drawer ? min(420, geometry.size.width * 0.55) : geometry.size.width)
                    .background(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(drawer ? 0.15 : 0), radius: 12)
            }
        }
    }
}
