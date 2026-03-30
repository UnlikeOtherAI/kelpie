import SwiftUI

/// URL bar with text input and navigation buttons. Pill-shaped URL field.
struct URLBarView: View {
    @ObservedObject var browserState: BrowserState
    let onNavigate: (String) -> Void
    let onBack: () -> Void
    let onForward: () -> Void

    @State private var urlText: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!browserState.canGoBack)

            Button(action: onForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!browserState.canGoForward)

            TextField("URL", text: $urlText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.URL)
                .onSubmit { navigate() }
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
