import SwiftUI

/// Main browser window: toolbar + renderer view + floating menu overlay.
struct BrowserView: View {
    @ObservedObject var browserState: BrowserState
    @ObservedObject var serverState: ServerState
    @ObservedObject var rendererState: RendererState
    @State private var showSettings = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Loading progress bar
                if browserState.isLoading {
                    ProgressView(value: browserState.progress)
                        .progressViewStyle(.linear)
                }

                // URL bar — fixed height, never compressed
                URLBarView(
                    browserState: browserState,
                    rendererState: rendererState,
                    onNavigate: { url in
                        guard let urlObj = URL(string: url) else { return }
                        serverState.handlerContext.load(url: urlObj)
                    },
                    onBack: { serverState.handlerContext.goBack() },
                    onForward: { serverState.handlerContext.goForward() },
                    onReload: { serverState.handlerContext.reloadPage() },
                    onSwitchRenderer: { engine in
                        Task {
                            await serverState.switchRenderer(to: engine)
                        }
                    }
                )
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

                // Renderer view — fills remaining space
                if rendererState.isSwitching {
                    VStack {
                        Spacer()
                        ProgressView("Switching renderer...")
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    RendererContainerView(serverState: serverState, rendererState: rendererState)
                        .frame(maxHeight: .infinity)
                }
            }

            // Floating action menu overlay
            FloatingMenuView(
                onReload: { serverState.handlerContext.reloadPage() },
                onSafariAuth: {
                    if let url = serverState.handlerContext.currentURL {
                        let helper = SafariAuthHelper()
                        helper.handlerContext = serverState.handlerContext
                        helper.authenticate(url: url)
                    }
                },
                onSettings: { showSettings = true },
                onBookmarks: { /* TODO: show bookmarks panel */ },
                onHistory: { /* TODO: show history panel */ },
                onNetworkInspector: { /* TODO: show network inspector */ }
            )
        }
        .onChange(of: browserState.currentURL) { _, newURL in
            HistoryStore.shared.record(url: newURL, title: browserState.pageTitle)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(serverState: serverState, rendererState: rendererState)
        }
        .onAppear {
            // Remove focus from URL bar on launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApplication.shared.keyWindow?.makeFirstResponder(nil)
            }

            if let renderer = serverState.handlerContext.renderer {
                renderer.onStateChange = { [weak browserState] in
                    Task { @MainActor in
                        guard let renderer = serverState.handlerContext.renderer else { return }
                        browserState?.currentURL = renderer.currentURL?.absoluteString ?? ""
                        browserState?.pageTitle = renderer.currentTitle
                        browserState?.isLoading = renderer.isLoading
                        browserState?.canGoBack = renderer.canGoBack
                        browserState?.canGoForward = renderer.canGoForward
                        browserState?.progress = renderer.estimatedProgress
                    }
                }
            }
        }
    }
}

/// Wraps the active renderer's NSView in SwiftUI.
struct RendererContainerView: NSViewRepresentable {
    @ObservedObject var serverState: ServerState
    @ObservedObject var rendererState: RendererState

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        if let view = serverState.handlerContext.renderer?.makeView() {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        container.subviews.forEach { $0.removeFromSuperview() }
        if let view = serverState.handlerContext.renderer?.makeView() {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
    }
}
