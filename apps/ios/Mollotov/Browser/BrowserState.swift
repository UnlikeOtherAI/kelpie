import Foundation
import Combine

/// Observable state shared between the browser UI and WebView coordinator.
final class BrowserState: ObservableObject {
    @Published var currentURL: String = "https://apple.com"
    @Published var pageTitle: String = ""
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var progress: Double = 0.0
    @Published var consoleMessages: [ConsoleMessage] = []

    struct ConsoleMessage: Identifiable {
        let id = UUID()
        let level: String
        let text: String
        let timestamp: Date
    }
}
