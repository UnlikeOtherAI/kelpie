import Foundation
import AppKit
import Combine
import WebKit

/// Everything a caller can ask for when opening a tab beyond its URL.
///
/// `dataStore` is resolved by the caller (the `new-tab` handler or the session
/// restore) rather than looked up here, because resolution can fail — an
/// invalid partition string, or one that is mid-teardown — and those failures
/// have to reach the HTTP response, not a tab constructor.
struct TabSpec {
    var name: String?
    var partition: String?
    var persistent = true
    var dataStore: WKWebsiteDataStore?
}

@MainActor
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    let renderer: WKWebViewRenderer
    let chatSession: AIChatSession
    #if !KELPIE_WEBKIT_ONLY
    var chromiumRenderer: CEFRenderer?
    #endif

    /// Storage container this tab is bound to; `nil` means the shared default
    /// store. Immutable: a tab cannot change identity mid-life, and a partition
    /// only makes sense for the web view it was built with.
    let partition: String?
    /// `false` when the partition's storage is in-memory only. Always `true`
    /// for an unpartitioned tab, which uses the persistent default store.
    let persistent: Bool

    /// Free-form display label. Published because the tab bar shows it in place
    /// of the page title.
    @Published var name: String?
    @Published var title: String = "Start Page"
    @Published var currentURL: String = "" {
        didSet {
            if currentURL != oldValue { chatSession.allowActions = false }
        }
    }
    @Published var isLoading: Bool = false
    @Published var favicon: NSImage?
    @Published var isStartPage: Bool = true

    /// Label shown in the tab bar: the caller-supplied name when there is one,
    /// otherwise the page title.
    var displayLabel: String {
        guard let name, !name.isEmpty else { return title }
        return name
    }

    private var lastHistoryURL: String = ""
    private var lastHistoryTitle: String = ""
    private var lastObservedHistoryClearGeneration = HistoryStore.shared.clearGeneration

    init(spec: TabSpec = TabSpec()) {
        self.name = spec.name
        self.partition = spec.partition
        self.persistent = spec.persistent
        self.renderer = WKWebViewRenderer(dataStore: spec.dataStore)
        self.chatSession = AIChatSession(tabId: id.uuidString)
        renderer.downloadTabId = id.uuidString
    }

    deinit {
        // Break WKUserContentController retain cycle before the renderer is released.
        // Tab is always created and destroyed on the main actor.
        MainActor.assumeIsolated {
            renderer.invalidate()
        }
    }

    func recordHistoryIfNeeded(url: String, title: String) {
        syncHistoryTrackingIfNeeded()
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, trimmedURL != lastHistoryURL else { return }

        lastHistoryURL = trimmedURL
        lastHistoryTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        HistoryStore.shared.record(url: trimmedURL, title: title)
    }

    func updateHistoryTitleIfNeeded(url: String, title: String) {
        syncHistoryTrackingIfNeeded()
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedTitle.isEmpty else { return }
        guard trimmedURL == lastHistoryURL, trimmedTitle != lastHistoryTitle else { return }

        lastHistoryTitle = trimmedTitle
        HistoryStore.shared.updateLatestTitle(for: trimmedURL, title: trimmedTitle)
    }

    private func syncHistoryTrackingIfNeeded() {
        let currentGeneration = HistoryStore.shared.clearGeneration
        guard currentGeneration != lastObservedHistoryClearGeneration else { return }
        lastObservedHistoryClearGeneration = currentGeneration
        lastHistoryURL = ""
        lastHistoryTitle = ""
    }
}

@MainActor
final class TabStore: ObservableObject {
    @Published private(set) var tabs: [Tab] = []
    @Published private(set) var activeTabID: UUID?
    private(set) var engine: RendererState.Engine = .webkit
    private(set) var isClosed = false

    var activeTab: Tab? { tabs.first { $0.id == activeTabID } }
    var activeRenderer: (any RendererEngine)? { activeTab.flatMap(renderer(for:)) }

    // Keyed by tab ID so unbind() can cancel cleanly.
    private var tabSinks: [UUID: AnyCancellable] = [:]
    private var sessionPersistence = true

    init(engine: RendererState.Engine = .webkit) {
        self.engine = engine
        var restoredTabs: [Tab] = []
        var activeIndex = 0
        // Index against the tabs that actually came back, not against the
        // persisted records: a dropped partitioned tab would otherwise shift
        // the selection onto the wrong tab.
        for record in SessionStore.load() {
            guard let tab = restore(record) else { continue }
            if record.isActive { activeIndex = restoredTabs.count }
            restoredTabs.append(tab)
        }
        if !restoredTabs.isEmpty {
            tabs = restoredTabs
            activeTabID = restoredTabs[min(activeIndex, restoredTabs.count - 1)].id
            return
        }

        let initial = Tab()
        bind(initial)
        tabs = [initial]
        activeTabID = initial.id
    }

    /// An isolated renderer harness owns an in-memory tab without restoring,
    /// observing or persisting a person's browser session/history.
    init(isolatedTab: Tab) {
        sessionPersistence = false
        tabs = [isolatedTab]
        activeTabID = isolatedTab.id
    }

    /// Rebuild one tab from its persisted record, or `nil` when it must not be
    /// restored: a non-persistent partition (its storage is gone), or a
    /// partition the registry no longer knows about (restoring it under a fresh
    /// store would fork the identity behind a familiar name).
    private func restore(_ record: SessionStore.TabRecord) -> Tab? {
        guard let url = URL(string: record.url) else { return nil }
        var spec = TabSpec(name: record.name)
        if let partition = record.partition {
            guard record.persistent, let resolved = PartitionRegistry.shared.rebind(id: partition) else {
                print("[TabStore] dropping restored tab for unavailable partition \"\(partition)\"")
                return nil
            }
            spec.partition = resolved.id
            spec.persistent = resolved.persistent
            spec.dataStore = resolved.dataStore
        }
        let tab = Tab(spec: spec)
        tab.isStartPage = false
        tab.currentURL = url.absoluteString
        bind(tab)
        if engine == .webkit { tab.renderer.load(url: url) }
        return tab
    }

    @discardableResult
    func addTab(spec: TabSpec = TabSpec()) -> Tab {
        NessieConnection.shared.personChangedTab()
        activeRenderer?.willDeactivate()
        let tab = Tab(spec: spec)
        bind(tab)
        tabs.append(tab)
        activeTabID = tab.id
        persistSession()
        return tab
    }

    func closeTab(id: UUID) {
        if id == activeTabID { NessieConnection.shared.personChangedTab() }
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }

        if tabs.count == 1 {
            unbind(tabs[0])
            let replacement = Tab()
            bind(replacement)
            tabs = [replacement]
            activeTabID = replacement.id
            persistSession()
            return
        }

        unbind(tabs[idx])
        tabs.remove(at: idx)
        if activeTabID == id {
            let newIdx = min(idx, tabs.count - 1)
            activeTabID = tabs[newIdx].id
        }
        persistSession()
    }

    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        if id != activeTabID {
            NessieConnection.shared.personChangedTab()
            activeRenderer?.willDeactivate()
        }
        activeTabID = id
        persistSession()
    }

    /// Everything a tab derives from its renderer's navigation state: title,
    /// URL, loading, history and the start page screenshot. The renderer has a
    /// single state callback, so whoever installs it (this store, or a window
    /// adopting the tab) must route through here.
    func rendererStateChanged(_ tab: Tab, from renderer: any RendererEngine) {
        guard renderer.engineName == engine.rawValue else { return }
        if engine == .chromium, tab.isStartPage { return }
        let rawTitle = renderer.currentTitle
        let nextURL = renderer.currentURL?.absoluteString ?? ""
        tab.title = rawTitle.isEmpty ? "Start Page" : rawTitle
        tab.currentURL = nextURL
        tab.isLoading = renderer.isLoading
        tab.recordHistoryIfNeeded(url: nextURL, title: rawTitle)
        tab.updateHistoryTitleIfNeeded(url: nextURL, title: rawTitle)
        capturePreviewIfSettled(tab)
    }

    private func bind(_ tab: Tab) {
        tab.renderer.onStateChange = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.rendererStateChanged(tab, from: tab.renderer)
        }
        tabSinks[tab.id] = tab.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.persistSession()
            }
    }

    /// Start page screenshots come from the person's own session only, never
    /// from an isolated renderer harness.
    private func capturePreviewIfSettled(_ tab: Tab) {
        guard sessionPersistence, engine == .webkit else { return }
        SitePreviewCapturer.shared.tabChanged(tab) { [weak self, weak tab] in
            guard let self, let tab else { return false }
            return self.activeTabID == tab.id
        }
    }

    private func unbind(_ tab: Tab) {
        SitePreviewCapturer.shared.tabClosed(tab.id)
        tab.chatSession.close()
        tab.renderer.onStateChange = nil
        #if !KELPIE_WEBKIT_ONLY
        tab.chromiumRenderer?.retire()
        tab.chromiumRenderer = nil
        #endif
        tabSinks.removeValue(forKey: tab.id)
    }

    func closeAll() {
        guard !isClosed else { return }
        isClosed = true
        persistSession()
        sessionPersistence = false
        for tab in tabs {
            unbind(tab)
            tab.renderer.invalidate()
        }
        tabs = []
        activeTabID = nil
    }

    private func persistSession() {
        guard sessionPersistence else { return }
        SessionStore.save(tabs: tabs, activeID: activeTabID)
    }

    func renderer(for tab: Tab) -> (any RendererEngine)? {
        if engine == .webkit { return tab.renderer }
        #if !KELPIE_WEBKIT_ONLY
        guard tab.partition == nil else { return nil }
        if let chromium = tab.chromiumRenderer { return chromium }
        let chromium = CEFRenderer(tabID: tab.id)
        tab.chromiumRenderer = chromium
        chromium.onStateChange = { [weak self, weak tab, weak chromium] in
            guard let self, let tab, let chromium else { return }
            self.rendererStateChanged(tab, from: chromium)
        }
        if !tab.isStartPage, let url = URL(string: tab.currentURL), !tab.currentURL.isEmpty {
            chromium.load(url: url)
        }
        return chromium
        #else
        return nil
        #endif
    }

    /// Reuse each tab's browser when it already holds the same URL. A Chromium
    /// tab which has never been shown stays lazy until its surface is selected.
    func selectEngine(_ engine: RendererState.Engine) {
        guard engine != self.engine else { return }
        activeRenderer?.willDeactivate()
        self.engine = engine
        for tab in tabs where !tab.isStartPage {
            guard !tab.currentURL.isEmpty, let url = URL(string: tab.currentURL) else { continue }
            let target: (any RendererEngine)?
            #if !KELPIE_WEBKIT_ONLY
            target = engine == .webkit ? tab.renderer : tab.chromiumRenderer
            #else
            target = tab.renderer
            #endif
            if let target, target.currentURL != url { target.load(url: url) }
        }
    }
}
