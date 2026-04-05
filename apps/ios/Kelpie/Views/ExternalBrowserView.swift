import SwiftUI
import WebKit

/// Fullscreen browser view for the Apple TV external display.
/// No URL bar or floating menu — controlled entirely from the CLI.
struct ExternalBrowserView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var serverState: ServerState

    var body: some View {
        WebViewContainer(
            browserState: browserState,
            handlerContext: serverState.handlerContext
        ) { wv in
            serverState.webView = wv
            serverState.handlerContext.webView = wv
        }
        .ignoresSafeArea()
        .onChange(of: browserState.currentURL) { newURL in
            HistoryStore.shared.record(url: newURL, title: browserState.pageTitle)
        }
        .onChange(of: browserState.pageTitle) { newTitle in
            HistoryStore.shared.updateLatestTitle(for: browserState.currentURL, title: newTitle)
        }
    }
}
