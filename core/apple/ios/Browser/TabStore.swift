import Foundation
import Combine
import WebKit

/// Manages the set of open browser tabs. Creates configured WKWebViews for new tabs.
@MainActor
final class TabStore: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var activeBrowserTabID: UUID? {
        didSet { if oldValue != activeBrowserTabID { NotificationCenter.default.post(name: .kelpieBrowserDocumentChanged, object: nil) } }
    }

    var activeBrowserTab: BrowserTab? { tabs.first { $0.id == activeBrowserTabID } }

    private weak var handlerContext: HandlerContext?
    private var persistsSession = true
    private var previewTabs: [UUID] = []
    private var tabSinks: [UUID: AnyCancellable] = [:]

    init(handlerContext: HandlerContext?) {
        self.handlerContext = handlerContext
        let session = SessionStore.load()
        if let session {
            let restoredTabs = restoredBrowserTabs(from: session.tabs)
            if !restoredTabs.isEmpty {
                tabs = restoredTabs
                let activeRecord = session.tabs.indices.contains(session.activeIndex) ? session.tabs[session.activeIndex] : nil
                activeBrowserTabID = restoredTabs.first { $0.currentURL == activeRecord?.url && $0.partition == activeRecord?.partition }?.id
                    ?? restoredTabs.first?.id
                return
            }
        }
        let showStartPage = !KelpieStorage.defaults.bool(forKey: "hideWelcomeCard")
        let tab = createBrowserTab(isStartPage: showStartPage)
        bind(tab)
        tabs = [tab]
        activeBrowserTabID = tab.id
        if !showStartPage {
            let homeURL = KelpieStorage.defaults.string(forKey: "homeURL") ?? defaultHomeURL
            if let url = URL(string: homeURL) {
                tab.webView.load(URLRequest(url: url))
            }
        }
    }

    /// Creates an isolated in-memory tab store for WebKit control tests.
    init(isolatedTab: BrowserTab) {
        persistsSession = false
        handlerContext = nil
        tabs = [isolatedTab]
        activeBrowserTabID = isolatedTab.id
    }

    @discardableResult
    func addBrowserTab(url: String? = nil) -> BrowserTab {
        addBrowserTab(url: url, dataStore: WebViewDefaults.sharedWebsiteDataStore)
    }

    @discardableResult
    func addBrowserTab(url: String?, dataStore: WKWebsiteDataStore, partition: String? = nil, name: String? = nil) -> BrowserTab {
        NessieConnection.shared.personChangedTab()
        captureActivePreview()
        let tab = createBrowserTab(dataStore: dataStore, partition: partition, name: name)
        bind(tab)
        tabs.append(tab)
        activeBrowserTabID = tab.id
        if let url, let parsed = URL(string: url) {
            tab.isStartPage = false
            tab.currentURL = url
            tab.webView.load(URLRequest(url: parsed))
        }
        persistSession()
        return tab
    }

    func closeBrowserTab(id: UUID) {
        if id == activeBrowserTabID { NessieConnection.shared.personChangedTab() }
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
        if id != activeBrowserTabID { NessieConnection.shared.personChangedTab() }
        guard tabs.contains(where: { $0.id == id }) else { return }
        if id != activeBrowserTabID { captureActivePreview() }
        activeBrowserTabID = id
        persistSession()
    }

    func captureActivePreview() {
        guard let tab = activeBrowserTab, !tab.isStartPage else { return }
        previewTabs.removeAll { $0 == tab.id }
        previewTabs.append(tab.id)
        while previewTabs.count > 12 {
            let oldest = previewTabs.removeFirst()
            tabs.first { $0.id == oldest }?.discardPreview()
        }
        tab.capturePreview()
    }

    private func createBrowserTab(
        isStartPage: Bool = true,
        dataStore: WKWebsiteDataStore? = nil,
        partition: String? = nil,
        name: String? = nil
    ) -> BrowserTab {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = dataStore ?? WebViewDefaults.sharedWebsiteDataStore

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

        return BrowserTab(webView: webView, isStartPage: isStartPage, partition: partition, name: name)
    }

    private func restoredBrowserTabs(from records: [SessionStore.TabRecord]) -> [BrowserTab] {
        records.compactMap { record in
            guard let url = URL(string: record.url) else { return nil }
            let dataStore: WKWebsiteDataStore
            do {
                dataStore = try record.partition.map { try MobilePartitionRegistry.shared.resolve($0, restoring: true) }
                    ?? WebViewDefaults.sharedWebsiteDataStore
            } catch {
                NSLog("[TabStore] Skipped unavailable isolated tab: %@", error.localizedDescription)
                return nil
            }
            let tab = createBrowserTab(isStartPage: false, dataStore: dataStore, partition: record.partition, name: record.name)
            bind(tab)
            tab.currentURL = record.url
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
        previewTabs.removeAll { $0 == tab.id }
        tabSinks.removeValue(forKey: tab.id)
    }

    func closeAll() {
        persistSession()
        persistsSession = false
        for tab in tabs { tab.invalidate(); unbind(tab) }
        tabs = []
        activeBrowserTabID = nil
    }

    private func persistSession() {
        guard persistsSession else { return }
        SessionStore.save(tabs: tabs, activeID: activeBrowserTabID)
    }
}
