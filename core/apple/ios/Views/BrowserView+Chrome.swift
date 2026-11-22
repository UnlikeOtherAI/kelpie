import SwiftUI

extension BrowserView {
    var bottomChrome: some View {
        BottomBarView(
            tabStore: tabStore,
            browserState: browserState,
            onNavigate: navigate,
            onBack: goBack,
            onForward: goForward,
            onReload: {
                if browserState.isLoading { browserState.webView?.stopLoading() } else { reload() }
            },
            onBookmarks: { showBookmarks = true },
            onDownloads: { showDownloads = true },
            is3DInspectorActive: isIn3DInspector,
            onSnapshot3D: { Task { @MainActor in await toggle3DInspector() } },
            onShowTabs: {
                tabStore.captureActivePreview()
                showTabOverview = true
                bottomBarCollapsed = false
            },
            isCollapsed: $bottomBarCollapsed,
            isEditing: $addressEditing,
            moreContent: browserMoreMenu
        )
    }

    /// How far the bottom bar sits inside the home-indicator safe area.
    var bottomBarSink: CGFloat { BottomBarMetrics.sink(bottomSafeArea: bottomSafeArea) }

    /// Web content clearance above the bottom safe area for the bar in either state.
    func bottomBarClearance(collapsed: Bool) -> CGFloat {
        let height = collapsed ? BottomBarMetrics.collapsedHeight : BottomBarMetrics.expandedHeight
        return max(0, height - bottomBarSink)
    }

    @ViewBuilder
    func browserMoreMenu(onSnapshot3D: (() -> Void)?) -> some View {
        Button { showHistory = true } label: { Label("History", systemImage: "clock") }
        Button { showAI = true } label: { Label("AI", systemImage: "sparkles") }
        Button { showNetworkInspector = true } label: { Label("Network inspector", systemImage: "network") }
        // The bottom-anchored iOS More menu lays out its actions upward.
        if let onSnapshot3D {
            Button(
                "3D inspector",
                systemImage: isIn3DInspector ? "cube.fill" : "cube.transparent",
                action: onSnapshot3D
            )
            .accessibilityIdentifier("browser.snapshot-3d.menu")
            .accessibilityValue(isIn3DInspector ? "On" : "Off")
        }
        if isPad {
            Menu("Viewport") {
                Button("Full width") { setTabletViewportPreset("") }
                ForEach(availableTabletViewportPresetOptions) { preset in
                    Button(preset.label) { toggleTabletViewportPreset(preset.id) }
                }
            }
        }
        Divider()
        Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
        Button(action: presentWelcomeFromHelp) { Label("Show welcome screen", systemImage: "hand.wave") }
    }

    func updateChromeSample() {
        guard isPad else { return }
        chromeSampler.update(webView: tabStore.activeBrowserTab?.isStartPage == true ? nil : browserState.webView) {
            chromeAppearance.setSample($0)
        }
        chromeSampler.requestSample()
    }
}
