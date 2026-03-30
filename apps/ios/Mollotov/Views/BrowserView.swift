import SwiftUI
import WebKit

/// Main browser screen: URL bar + WKWebView + settings button.
struct BrowserView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var serverState: ServerState
    @State private var showSettings = false
    @State private var webView: WKWebView?
    private let safariAuth = SafariAuthHelper()

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
                showSettings: $showSettings,
                onNavigate: { url in
                    guard let webView, let urlObj = URL(string: url) else { return }
                    webView.load(URLRequest(url: urlObj))
                },
                onBack: { webView?.goBack() },
                onForward: { webView?.goForward() },
                onReload: { webView?.reload() },
                onSafariAuth: {
                    guard let webView, let url = webView.url else { return }
                    safariAuth.authenticate(url: url, webView: webView, from: webView.window) {}
                }
            )

            // WebView
            WebViewContainer(browserState: browserState, handlerContext: serverState.handlerContext) { wv in
                webView = wv
                serverState.webView = wv
                serverState.handlerContext.webView = wv
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(isPresented: $showSettings) {
            SettingsView(serverState: serverState)
        }
    }
}
