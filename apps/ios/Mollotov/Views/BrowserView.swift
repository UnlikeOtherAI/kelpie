import SwiftUI
import WebKit

/// Main browser screen: URL bar + WKWebView + floating action menu.
struct BrowserView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var serverState: ServerState
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var showHistory = false
    @State private var showNetworkInspector = false
    @State private var webView: WKWebView?
    private let safariAuth = SafariAuthHelper()

    var body: some View {
        ZStack {
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
                    onForward: { webView?.goForward() }
                )

                // WebView
                WebViewContainer(browserState: browserState, handlerContext: serverState.handlerContext) { wv in
                    webView = wv
                    serverState.webView = wv
                    serverState.handlerContext.webView = wv
                }
            }

            // Floating action menu overlay
            FloatingMenuView(
                onReload: { webView?.reload() },
                onSafariAuth: {
                    guard let webView, let url = webView.url else { return }
                    safariAuth.authenticate(url: url, webView: webView, from: webView.window) {}
                },
                onSettings: { showSettings = true },
                onBookmarks: { showBookmarks = true },
                onHistory: { showHistory = true },
                onNetworkInspector: { showNetworkInspector = true }
            )
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onChange(of: browserState.currentURL) { newURL in
            HistoryStore.shared.record(url: newURL, title: browserState.pageTitle)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(serverState: serverState)
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView(onNavigate: { url in
                guard let webView, let urlObj = URL(string: url) else { return }
                webView.load(URLRequest(url: urlObj))
            })
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(onNavigate: { url in
                guard let webView, let urlObj = URL(string: url) else { return }
                webView.load(URLRequest(url: urlObj))
            })
        }
        .sheet(isPresented: $showNetworkInspector) {
            NetworkInspectorView()
        }
    }
}
