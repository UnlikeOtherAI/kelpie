import Foundation
import Combine
import WebKit

/// Default home page — Kelpie GitHub Pages site.
let defaultHomeURL = "https://unlikeotherai.github.io/kelpie"

enum WebViewDefaults {
    static let sharedWebsiteDataStore = WKWebsiteDataStore.default()
    static let sharedUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
}

/// Observable state shared between the browser UI and WebView coordinator.
final class BrowserState: ObservableObject {
    @Published var currentURL: String = UserDefaults.standard.string(forKey: "homeURL") ?? defaultHomeURL
    @Published var isStartPage: Bool = !UserDefaults.standard.bool(forKey: "hideWelcomeCard")
    @Published var pageTitle: String = ""
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var progress: Double = 0.0
    @Published var consoleMessages: [ConsoleMessage] = []
    @Published var webView: WKWebView?

    struct ConsoleMessage: Identifiable {
        let id = UUID()
        let level: String
        let text: String
        let timestamp: Date
    }
}
