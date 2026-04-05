import Foundation
import AppKit
import Combine

@MainActor
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    let renderer: WKWebViewRenderer

    @Published var title: String = "Start Page"
    @Published var currentURL: String = ""
    @Published var isLoading: Bool = false
    @Published var favicon: NSImage? = nil

    init() {
        self.renderer = WKWebViewRenderer()
    }

    deinit {
        // Break WKUserContentController retain cycle before the renderer is released.
        // Tab is always created and destroyed on the main actor.
        MainActor.assumeIsolated {
            renderer.invalidate()
        }
    }
}

@MainActor
final class TabStore: ObservableObject {
    @Published private(set) var tabs: [Tab] = []
    @Published private(set) var activeTabID: UUID?

    var activeTab: Tab? { tabs.first { $0.id == activeTabID } }

    // Keyed by tab ID so unbind() can cancel cleanly.
    private var faviconSinks: [UUID: AnyCancellable] = [:]

    init() {
        let initial = Tab()
        tabs = [initial]
        activeTabID = initial.id
        bind(initial)
    }

    @discardableResult
    func addTab() -> Tab {
        let tab = Tab()
        bind(tab)
        tabs.append(tab)
        activeTabID = tab.id
        return tab
    }

    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }

        if tabs.count == 1 {
            unbind(tabs[0])
            let replacement = Tab()
            tabs = [replacement]
            activeTabID = replacement.id
            bind(replacement)
            return
        }

        unbind(tabs[idx])
        tabs.remove(at: idx)
        if activeTabID == id {
            let newIdx = min(idx, tabs.count - 1)
            activeTabID = tabs[newIdx].id
        }
    }

    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
    }

    private func bind(_ tab: Tab) {
        tab.renderer.onStateChange = { [weak tab, weak renderer = tab.renderer] in
            guard let tab, let renderer else { return }
            tab.title = renderer.currentTitle.isEmpty ? "Start Page" : renderer.currentTitle
            tab.currentURL = renderer.currentURL?.absoluteString ?? ""
            tab.isLoading = renderer.isLoading
        }
        faviconSinks[tab.id] = tab.$favicon
            .dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    private func unbind(_ tab: Tab) {
        tab.renderer.onStateChange = nil
        faviconSinks.removeValue(forKey: tab.id)
    }
}
