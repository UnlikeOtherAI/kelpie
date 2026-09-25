import SwiftUI

extension BrowserView {
    var chromeUnderlap: CGFloat {
        guard #available(macOS 26.0, *), rendererState.activeEngine == .webkit,
              viewportState.mode == .full, !serverState.isScriptRecording,
              tabStore.activeTab?.isStartPage != true else { return 0 }
        return 32 + (isChromeCollapsed ? 0 : 73)
    }

    var browserTabs: some View {
        HStack(spacing: 0) {
            if rendererState.activeEngine == .chromium {
                HStack(spacing: 12) {
                    Image("ChromeLogo").resizable().frame(width: 16, height: 16)
                    Text(tabStore.activeTab?.isStartPage == true ? "Start Page" : windowTitle)
                        .font(.system(size: 12)).lineLimit(1)
                    AppKitToolbarButton(
                    systemName: "xmark",
                    accessibilityID: "browser.tabs.close",
                    accessibilityLabel: "Close window"
                ) { NSApp.keyWindow?.close() }
                }
                .padding(.leading, 14)
                .frame(width: 210, height: 28)
                .background(BrowserChromeStyle.surface, in: UnevenRoundedRectangle(topLeadingRadius: 9, topTrailingRadius: 9))
                .padding(.top, 4)
                Spacer(minLength: 0)
            } else {
                TabBarView(
                    tabStore: tabStore,
                    onNewTab: handleNewTabCommand,
                    onCloseTab: { id in
                        isChromeCollapsed = false
                        let wasActive = tabStore.activeTabID == id
                        tabStore.closeTab(id: id)
                        if wasActive, let next = tabStore.activeTab { activateTab(next) }
                    },
                    onSelectTab: { id in
                        tabStore.selectTab(id: id)
                        if let tab = tabStore.activeTab { activateTab(tab) }
                    }
                )
            }
        }
        .frame(height: 32)

        .zIndex(2)
    }

    func showStartPage() {
        isChromeCollapsed = false
        guard let blank = URL(string: "about:blank") else { return }
        serverState.handlerContext.load(url: blank)
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
