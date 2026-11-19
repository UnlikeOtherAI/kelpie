import SwiftUI

extension BrowserView {
    var chromeUnderlap: CGFloat {
        guard #available(macOS 26.0, *), rendererState.activeEngine == .webkit,
              viewportState.mode == .full, !serverState.isScriptRecording,
              tabStore.activeTab?.isStartPage != true else { return 0 }
        return BrowserChromeLayout.underlap(collapsed: isChromeCollapsed, hasBookmarks: !bookmarkStore.nodes.isEmpty)
    }

    var browserTabs: some View {
        HStack(spacing: 0) {
            TabBarView(
                appearance: chromeAppearance,
                tabStore: tabStore,
                onNewTab: handleNewTabCommand,
                onCloseTab: { id in
                    guard !rendererState.isSwitching else { return }
                    isChromeCollapsed = false
                    let wasActive = tabStore.activeTabID == id
                    tabStore.closeTab(id: id)
                    if wasActive, let next = tabStore.activeTab { activateTab(next) }
                },
                onSelectTab: { id in
                    guard !rendererState.isSwitching else { return }
                    tabStore.selectTab(id: id)
                    if let tab = tabStore.activeTab { activateTab(tab) }
                }
            )
        }
        .frame(height: 32)
        .background(BrowserChromeStyle.tabs)

        .zIndex(2)
    }

    func addCurrentBookmark() {
        isChromeCollapsed = false
        bookmarkStore.addPage(
            title: browserState.pageTitle,
            url: browserState.currentURL,
            isStartPage: tabStore.activeTab?.isStartPage == true
        )
    }

    func showStartPage() {
        isChromeCollapsed = false
        guard let blank = URL(string: "about:blank") else { return }
        serverState.handlerContext.load(url: blank, windowId: windowId)
        tabStore.activeTab?.isStartPage = true
        tabStore.activeTab?.title = "Start Page"
        tabStore.activeTab?.favicon = nil
    }
}

/// Pure direction policy, shared by the native event monitor and focused regression tests.
enum BrowserChromeScroll {
    static func collapsed(deltaX: CGFloat, deltaY: CGFloat) -> Bool? {
        guard abs(deltaY) > 0.01, abs(deltaY) > abs(deltaX) else { return nil }
        return deltaY < 0
    }
}
