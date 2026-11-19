import Foundation

@MainActor
extension HandlerContext {
    /// Side-effects every navigation must run regardless of which renderer is
    /// driven: notify the shell (URL-bar / loading UI) and tear down the 3D
    /// inspector. Exposed so handlers can drive the resolved renderer directly,
    /// keeping navigate targeting the same renderer that reads resolve to even
    /// when no window has rendered to wire `renderer` to the active tab.
    func prepareForNavigation(windowId: String? = nil) {
        resolveWindow(windowId: windowId, tabId: nil)?.callbacks?.onWillLoad()
        if isIn3DInspector { mark3DInspectorInactive(notify: true) }
    }

    func load(url: URL, windowId: String? = nil) {
        prepareForNavigation(windowId: windowId)
        chromeRenderer(windowId: windowId)?.load(url: url)
    }

    var currentURL: URL? { renderer?.currentURL }
    var currentTitle: String { renderer?.currentTitle ?? "" }
    var isLoadingPage: Bool { renderer?.isLoading ?? false }
    var pageCanGoBack: Bool { renderer?.canGoBack ?? false }
    var pageCanGoForward: Bool { renderer?.canGoForward ?? false }

    func goBack(windowId: String? = nil) {
        prepareForNavigation(windowId: windowId)
        chromeRenderer(windowId: windowId)?.goBack()
    }

    func goForward(windowId: String? = nil) {
        prepareForNavigation(windowId: windowId)
        chromeRenderer(windowId: windowId)?.goForward()
    }

    func reloadPage(windowId: String? = nil) {
        guard let target = chromeRenderer(windowId: windowId) else { return }
        if isIn3DInspector {
            Task { @MainActor in
                await exit3DInspectorIfNeeded(notify: true)
                target.reload()
            }
            return
        }
        target.reload()
    }

    func hardReloadPage(windowId: String? = nil) {
        guard let target = chromeRenderer(windowId: windowId) else { return }
        if isIn3DInspector {
            Task { @MainActor in
                await exit3DInspectorIfNeeded(notify: true)
                target.hardReload()
            }
            return
        }
        target.hardReload()
    }

    private func chromeRenderer(windowId: String?) -> (any RendererEngine)? {
        guard let windowId, !activeEngineIsChromium else { return renderer }
        return resolveWindow(windowId: windowId, tabId: nil)?.tabStore.activeTab?.renderer
    }
}
