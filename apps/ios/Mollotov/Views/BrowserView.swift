import SwiftUI
import WebKit

/// Main browser screen: URL bar + WKWebView + settings button.
struct BrowserView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var serverState: ServerState
    @State private var showSettings = false
    @State private var webView: WKWebView?

    var body: some View {
        VStack(spacing: 0) {
            // Loading progress bar
            if browserState.isLoading {
                ProgressView(value: browserState.progress)
                    .progressViewStyle(.linear)
            }

            // URL bar
            URLBarView(
                browserState: browserState,
                onNavigate: { url in
                    guard let webView, let urlObj = URL(string: url) else { return }
                    webView.load(URLRequest(url: urlObj))
                },
                onBack: { webView?.goBack() },
                onForward: { webView?.goForward() },
                onReload: { webView?.reload() }
            )

            // WebView
            WebViewContainer(browserState: browserState) { wv in
                webView = wv
                serverState.webView = wv
            }

            // Bottom toolbar
            HStack {
                Spacer()
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                        .font(.title2)
                }
                .padding()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(serverState: serverState)
        }
    }
}
