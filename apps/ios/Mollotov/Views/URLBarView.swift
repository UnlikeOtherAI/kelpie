import SwiftUI

/// URL bar with text input, navigation buttons, and loading indicator.
struct URLBarView: View {
    @ObservedObject var browserState: BrowserState
    let onNavigate: (String) -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let onReload: () -> Void

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
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.URL)
                .onSubmit { navigate() }

            if browserState.isLoading {
                Button(action: {}) {
                    Image(systemName: "xmark")
                }
            } else {
                Button(action: onReload) {
                    Image(systemName: "arrow.clockwise")
                }
            }
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
