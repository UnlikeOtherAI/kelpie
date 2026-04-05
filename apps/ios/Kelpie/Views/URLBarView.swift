import SwiftUI

/// URL bar with text input and navigation buttons. Pill-shaped URL field.
struct URLBarView: View {
    @ObservedObject var browserState: BrowserState
    let onNavigate: (String) -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let showAI: Bool
    let onAI: () -> Void
    let onSnapshot3D: () -> Void

    @State private var urlText: String = ""
    private let navigationButtonSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: navigationButtonSize, height: navigationButtonSize)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("browser.nav.back")
            .disabled(!browserState.canGoBack)

            Button(action: onForward) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: navigationButtonSize, height: navigationButtonSize)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("browser.nav.forward")
            .disabled(!browserState.canGoForward)

            TextField("URL", text: $urlText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.URL)
                .accessibilityIdentifier("browser.url.field")
                .onSubmit { navigate() }

            if showAI {
                Button(action: onAI) {
                    Image(systemName: "brain")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: navigationButtonSize, height: navigationButtonSize)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .accessibilityIdentifier("browser.ai.button")
            }

            Button(action: onSnapshot3D) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: navigationButtonSize, height: navigationButtonSize)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("browser.snapshot-3d.button")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear { urlText = browserState.currentURL }
        .onChange(of: browserState.currentURL) { newURL in
            urlText = newURL
        }
    }

    private func navigate() {
        var url = urlText.trimmingCharacters(in: .whitespaces)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://\(url)"
        }
        onNavigate(url)
    }
}
