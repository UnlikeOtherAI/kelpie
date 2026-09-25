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
                if browserState.isLoading { browserState.webView?.stopLoading() }
                else { reload() }
            },
            onBookmarks: { showBookmarks = true },
            onShowTabs: {
                tabStore.activeBrowserTab?.capturePreview()
                showTabOverview = true
                bottomBarCollapsed = false
            },
            isCollapsed: $bottomBarCollapsed,
            isEditing: $addressEditing,
            moreContent: { browserMoreMenu }
        )
    }

    @ViewBuilder
    var browserMoreMenu: some View {
        Button { showHistory = true } label: { Label("History", systemImage: "clock") }
        Button(action: authenticateInSafari) { Label("Sign in with Safari", systemImage: "safari") }
        Button { showAI = true } label: { Label("AI", systemImage: "sparkles") }
        Button { showNetworkInspector = true } label: { Label("Network inspector", systemImage: "network") }
        if FeatureFlags.is3DInspectorEnabled {
            Button { Task { @MainActor in await toggle3DInspector() } } label: {
                Label("3D inspector", systemImage: "cube.transparent")
            }
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
