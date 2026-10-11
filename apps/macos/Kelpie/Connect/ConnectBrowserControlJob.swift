import Foundation
import WebKit

/// One immutable renderer/document authority for one canonical account request.
/// It is retained by the gateway's pending callback until the native operation retires.
@MainActor
final class ConnectBrowserControlJob {
    private let context: HandlerContext
    private let owner: Router
    private let tabID: String
    private let expectedVersion: String
    private let command: [String: Any]
    private let authorized: () -> Bool
    private let currentVersion: () -> String?
    private let stillPinned: () -> Bool
    private let active: () -> Bool
    private let accountSurface: () -> Bool
    private let router = Router()

    init(
        source: HandlerContext,
        owner: Router,
        command: [String: Any],
        tabID: String,
        expectedVersion: String,
        authorized: @escaping () -> Bool
    ) throws {
        guard let id = UUID(uuidString: tabID) else { throw ConnectBrowser.Failure("Tab not found") }
        self.owner = owner
        self.command = command
        self.tabID = tabID
        self.expectedVersion = expectedVersion
        self.authorized = authorized

        let pinned = HandlerContext()
        pinned.scriptPlaybackState = source.scriptPlaybackState
        #if os(iOS)
        guard let store = source.tabStore, let tab = store.tabs.first(where: { $0.id == id }) else {
            throw ConnectBrowser.Failure("Tab not found")
        }
        let view = tab.webView
        pinned.webView = view
        pinned.tabStore = store
        context = pinned
        currentVersion = { view.isLoading ? nil : ConnectDocument.version(view) }
        stillPinned = { store.tabs.contains { $0.id == id && $0.webView === view } }
        active = { store.activeBrowserTabID == id && store.activeBrowserTab?.webView === view }
        accountSurface = { Self.isAccountURL(view.url?.absoluteString) }
        #else
        if source.activeEngineIsChromium, let renderer = source.renderer as? CEFRenderer,
           renderer.connectionTabID == tabID, let bridge = renderer.bridge {
            pinned.renderer = renderer
            pinned.activeEngineIsChromium = true
            context = pinned
            currentVersion = { bridge.isLoading() ? nil : bridge.documentVersion() }
            stillPinned = { source.activeEngineIsChromium && source.renderer === renderer && renderer.bridge === bridge }
            active = { source.activeEngineIsChromium && source.renderer === renderer && renderer.bridge === bridge }
            accountSurface = { Self.isAccountURL(renderer.currentURL?.absoluteString) }
        } else {
            guard let entry = WindowRegistry.shared.entry(containingTabId: id),
                  let tab = entry.tabStore.tabs.first(where: { $0.id == id }) else {
                throw ConnectBrowser.Failure("Tab not found")
            }
            let renderer = tab.renderer
            pinned.renderer = renderer
            context = pinned
            currentVersion = { renderer.isLoading ? nil : ConnectDocument.version(renderer) }
            stillPinned = {
                !source.activeEngineIsChromium && source.renderer === renderer
                    && WindowRegistry.shared.entry(containingTabId: id)?.tabStore.tabs.contains {
                        $0.id == id && $0.renderer === renderer
                    } == true
            }
            active = {
                !source.activeEngineIsChromium && source.renderer === renderer
                    && entry.tabStore.activeTabID == id && entry.tabStore.activeTab?.renderer === renderer
            }
            accountSurface = { Self.isAccountURL(renderer.currentURL?.absoluteString) }
        }
        #endif

        #if os(macOS)
        pinned.browserControlEngineName = pinned.renderer?.engineName
        #endif
        pinned.remoteDocumentGuard = { [weak self] in
            guard let self else { return false }
            return self.authorized() && self.stillPinned() && self.active() && !self.accountSurface()
                && self.currentVersion() == self.expectedVersion
        }
        router.handlerContext = pinned
        router.scriptPlaybackState = pinned.scriptPlaybackState
        router.browserReferenceOwner = owner
        NavigationHandler(context: pinned).register(on: router)
        ScreenshotHandler(context: pinned).register(on: router)
        InteractionHandler(context: pinned).register(on: router)
        ScrollHandler(context: pinned).register(on: router)
        ConnectSnapshot(context: pinned).register(on: router)
    }

    func dispatch(method: String, params: [String: Any], mutates: Bool) async -> [String: Any] {
        guard authorized(), stillPinned(), !accountSurface() else {
            return errorResponse(code: "ACCESS_DENIED", message: "The account job is no longer authorized")
        }
        if mutates { owner.invalidateAllBrowserReferences() }
        if method == "browser-control-evaluate" {
            guard params["tabId"] as? String == tabID,
                  params["expression"] is String,
                  active(), currentVersion() == expectedVersion,
                  context.remoteDocumentGuard?() == true else {
                return errorResponse(code: "TAB_CHANGED", message: "The pinned document changed")
            }
            guard let expression = params["expression"] as? String else {
                return errorResponse(code: "NO_WEBVIEW", message: "The pinned renderer is unavailable")
            }
            #if os(iOS)
            guard let view = context.webView else {
                return errorResponse(code: "NO_WEBVIEW", message: "The pinned renderer is unavailable")
            }
            #else
            guard let renderer = try? context.resolveRenderer(tabId: tabID) else {
                return errorResponse(code: "NO_WEBVIEW", message: "The pinned renderer is unavailable")
            }
            #endif
            do {
                guard authorized(), active(), currentVersion() == expectedVersion else {
                    return errorResponse(code: "TAB_CHANGED", message: "The pinned document changed")
                }
                #if os(iOS)
                let value = try await BrowserControlWebKit.evaluate(expression, in: view)
                #else
                let value = try await renderer.evaluateBrowserControlJS(expression)
                #endif
                guard authorized(), stillPinned(), active(), !accountSurface(), currentVersion() == expectedVersion else {
                    return errorResponse(code: "TAB_CHANGED", message: "The pinned document changed")
                }
                return successResponse(["result": value ?? NSNull()])
            } catch {
                return errorResponse(code: "WEBVIEW_ERROR", message: "The pinned browser operation was interrupted")
            }
        }

        if ["get-tabs", "new-tab", "switch-tab", "close-tab"].contains(method) {
            guard authorized() else { return errorResponse(code: "ACCESS_DENIED", message: "The account job expired") }
            return await owner.browserDispatch(method: method, params: params, pinnedTabId: nil)
        }
        guard params["tabId"] as? String == tabID,
              currentVersion() == expectedVersion,
              active(), !accountSurface(), context.remoteDocumentGuard?() == true else {
            return errorResponse(code: "TAB_CHANGED", message: "The pinned document changed")
        }
        if ["navigate", "back", "forward", "reload"].contains(method) {
            return await navigation(method: method, params: params)
        }
        let result = await router.handle(method: method, body: params, browserGatewayDispatch: true).json
        guard authorized(), stillPinned(), active(), !accountSurface(), currentVersion() == expectedVersion else {
            return errorResponse(code: "TAB_CHANGED", message: "The pinned document changed")
        }
        return result
    }

    private func navigation(method: String, params: [String: Any]) async -> [String: Any] {
        var leasedDocumentOwner: AnyObject?
        #if os(macOS)
        if let renderer = context.renderer as? CEFRenderer, let bridge = renderer.bridge {
            let count = bridge.documentNavigationCount()
            let changesDocument = method == "navigate" || method == "reload"
                || (method == "back" ? renderer.canGoBack : method == "forward" ? renderer.canGoForward : false)
            let destination = method == "navigate" ? params["url"] as? String : nil
            context.remoteNavigationWaitGuard = { [weak self] in
                guard let self else { return false }
                return self.authorized() && self.stillPinned() && self.active() && !self.accountSurface()
                    && bridge.documentNavigationCount() <= count + 1
            }
            context.remoteNavigationReadGuard = { [weak self] in
                guard let self, self.authorized(), self.stillPinned(), self.active(), !self.accountSurface(), !bridge.isLoading(),
                      bridge.documentNavigationCount() == count + (changesDocument ? 1 : 0) else { return false }
                return ConnectBrowser.navigationDestinationMatches(current: bridge.currentURL(), destination: destination)
            }
        } else {
            guard let renderer = context.renderer as? WKWebViewRenderer,
                  let view = renderer.makeView() as? WKWebView else {
                return errorResponse(code: "NO_WEBVIEW", message: "The pinned renderer is unavailable")
            }
            leasedDocumentOwner = renderer
            installWebKitNavigationLease(view, documentOwner: renderer)
        }
        #else
        guard let view = context.webView else { return errorResponse(code: "NO_WEBVIEW", message: "The pinned renderer is unavailable") }
        leasedDocumentOwner = view
        installWebKitNavigationLease(view, documentOwner: view)
        #endif
        defer { if let leasedDocumentOwner { ConnectDocument.reserve(leasedDocumentOwner, lease: nil) } }
        let result = await router.handle(method: method, body: params, browserGatewayDispatch: true).json
        guard result["success"] as? Bool == true else { return result }
        do {
            try await context.waitForNavigationRead()
            guard authorized(), stillPinned(), active(), !accountSurface() else { throw CancellationError() }
            return result
        } catch {
            return errorResponse(code: "TAB_CHANGED", message: "Navigation lost its job-owned document")
        }
    }

    private func installWebKitNavigationLease(_ view: WKWebView, documentOwner: AnyObject) {
        let lease = ConnectNavigationLease(initial: expectedVersion)
        ConnectDocument.reserve(documentOwner, lease: lease)
        context.remoteNavigationReadGuard = { [weak self] in
            guard let self else { return false }
            return lease.allowsRead(
                version: ConnectDocument.version(documentOwner),
                loading: view.isLoading,
                authorized: self.authorized() && self.stillPinned() && self.active() && !self.accountSurface()
            )
        }
        context.remoteNavigationWaitGuard = { [weak self] in
            guard let self else { return false }
            return lease.allowsWait(
                version: ConnectDocument.version(documentOwner),
                authorized: self.authorized() && self.stillPinned() && self.active() && !self.accountSurface()
            )
        }
    }

    private static func isAccountURL(_ raw: String?) -> Bool {
        URLComponents(string: raw ?? "")?.host?.lowercased() == "authentication.unlikeotherai.com"
    }
}
