import Foundation
import Combine
import WebKit

/// Manages the set of open browser tabs. Creates configured WKWebViews for new tabs.
@MainActor
final class TabStore: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var activeBrowserTabID: UUID?

    var activeBrowserTab: BrowserTab? { tabs.first { $0.id == activeBrowserTabID } }

    private weak var handlerContext: HandlerContext?
    private var tabSinks: [UUID: AnyCancellable] = [:]

    init(handlerContext: HandlerContext?) {
        self.handlerContext = handlerContext
        let session = SessionStore.load()
        if let session {
            let restoredTabs = restoredBrowserTabs(from: session.urls)
            if !restoredTabs.isEmpty {
                tabs = restoredTabs
                activeBrowserTabID = restoredTabs[min(session.activeIndex, restoredTabs.count - 1)].id
                return
            }
        }
        let showStartPage = !UserDefaults.standard.bool(forKey: "hideWelcomeCard")
        let tab = createBrowserTab(isStartPage: showStartPage)
        bind(tab)
        tabs = [tab]
        activeBrowserTabID = tab.id
        if !showStartPage {
            let homeURL = UserDefaults.standard.string(forKey: "homeURL") ?? defaultHomeURL
            if let url = URL(string: homeURL) {
                tab.webView.load(URLRequest(url: url))
            }
        }
    }

    @discardableResult
    func addBrowserTab(url: String? = nil) -> BrowserTab {
        let tab = createBrowserTab()
        bind(tab)
        tabs.append(tab)
        activeBrowserTabID = tab.id
        if let url, let parsed = URL(string: url) {
            tab.isStartPage = false
            tab.webView.load(URLRequest(url: parsed))
        }
        persistSession()
        return tab
    }

    func closeBrowserTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        if tabs.count == 1 {
            let replacement = createBrowserTab()
            tabs[0].invalidate()
            unbind(tabs[0])
            tabs = [replacement]
            activeBrowserTabID = replacement.id
            bind(replacement)
            persistSession()
            return
        }

        let tab = tabs.remove(at: index)
        tab.invalidate()
        unbind(tab)
        if activeBrowserTabID == id {
            activeBrowserTabID = tabs[min(index, tabs.count - 1)].id
        }
        persistSession()
    }

    func selectBrowserTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeBrowserTabID = id
        persistSession()
    }

    private func createBrowserTab(isStartPage: Bool = true) -> BrowserTab {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = WebViewDefaults.sharedWebsiteDataStore

        if let handlerContext {
            let ucc = config.userContentController
            let proxy = WeakScriptMessageHandler(handlerContext)
            ucc.addUserScript(NetworkBridge.bridgeScript)
            ucc.add(proxy, name: "kelpieNetwork")
            ucc.addUserScript(WebSocketBridge.bridgeScript)
            ucc.addUserScript(ConsoleHandler.bridgeScript)
            ucc.add(proxy, name: "kelpieConsole")
            ucc.add(proxy, name: "kelpie3DSnapshot")
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = WebViewDefaults.sharedUserAgent

        return BrowserTab(webView: webView, isStartPage: isStartPage)
    }

    private func restoredBrowserTabs(from urls: [String]) -> [BrowserTab] {
        urls.compactMap { value in
            guard let url = URL(string: value) else { return nil }
            let tab = createBrowserTab(isStartPage: false)
            bind(tab)
            tab.webView.load(URLRequest(url: url))
            return tab
        }
    }

    private func bind(_ tab: BrowserTab) {
        tabSinks[tab.id] = tab.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.persistSession()
            }
        }
    }

    private func unbind(_ tab: BrowserTab) {
        tabSinks.removeValue(forKey: tab.id)
    }

    private func persistSession() {
        SessionStore.save(tabs: tabs, activeID: activeBrowserTabID)
    }
}
