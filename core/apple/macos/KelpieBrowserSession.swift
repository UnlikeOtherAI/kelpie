import AppKit
import SwiftUI

/// One browser runtime; each surface owns its tabs independently of its host view.
@MainActor
public final class KelpieBrowserSession: ObservableObject {
    public let connectionInstallationID: String
    let browserState = BrowserState()
    let rendererState = RendererState()
    let serverState: ServerState
    private let localControlEnabled: Bool
    private var started = false
    private var closed = false
    var isClosed: Bool { closed }
    private var browserMenu: EmbeddedBrowserMenu?
    private let runtimeID = UUID()
    private var surfaces: [WeakBrowserSurface] = []
    private var windows: [NSWindow] = []
    private var regions: [WeakBrowserRegion] = []

    /// - Parameter downloadsDirectory: where downloads are saved for this process;
    ///   `nil` keeps the user's Downloads folder. Sandboxed or verification hosts
    ///   can choose a folder they are allowed to write without a consent prompt.
    public init(
        uoaSession: KelpieUOASession? = nil,
        port: UInt16 = 8420,
        localControlEnabled: Bool = true,
        downloadsDirectory: URL? = nil
    ) {
        connectionInstallationID = NessieConnection.shared.installationID
        if let downloadsDirectory { DownloadStore.shared.directoryProvider = { downloadsDirectory } }
        serverState = ServerState(port: port)
        self.localControlEnabled = localControlEnabled
        if let uoaSession { UOAAccount.shared.useHostSession(uoaSession) }
        KelpieBrowserProfile.acquire(runtimeID)
    }

    /// Preserves the standalone CLI launch contract, including background launches.
    public static func standalone(arguments: [String] = ProcessInfo.processInfo.arguments) -> KelpieBrowserSession {
        let session = KelpieBrowserSession(port: standalonePort(arguments: arguments))
        Task { @MainActor in session.start() }
        return session
    }

    static func standalonePort(arguments: [String]) -> UInt16 {
        guard let index = arguments.firstIndex(of: "--port"),
              arguments.indices.contains(index + 1),
              let port = UInt16(arguments[index + 1]), port > 0 else { return 8420 }
        return port
    }

    public var websiteDataIsPersistent: Bool { KelpieWebsiteData.store.isPersistent }

    public func start() {
        guard !started, !closed else { return }
        started = true
        _ = AIState.shared
        serverState.startHTTPServer(rendererState: rendererState, listen: localControlEnabled)
        UOALoginCookies.context = serverState.handlerContext
        startCookieSync()
        NessieConnection.shared.acceptsPersonEvent = { [weak self] event in self?.contains(event) == true }
        NessieConnection.shared.start(context: serverState.handlerContext)
        UOAAccount.shared.restoreSession()
    }

    /// Cookie sync belongs to the standalone app; embedded hosts never run it. It follows
    /// the account from before the session restore, so a restored sign-in starts it.
    private func startCookieSync() {
        guard KelpieStorage.standalone else { return }
        let sync = MacCookieSync(defaultCookies: serverState.handlerContext.defaultCookies)
        serverState.handlerContext.cookieSync = sync
        sync.start()
    }

    public func setForeground(_ foreground: Bool) {
        guard !closed else { return }
        NessieConnection.shared.setForeground(foreground)
    }

    public func makeSurface(ownsWindowChrome: Bool = false) -> KelpieBrowserSurface {
        precondition(!closed, "A closed browser session cannot create another surface")
        let surface = KelpieBrowserSurface(session: self, ownsWindowChrome: ownsWindowChrome)
        surfaces.removeAll { $0.value == nil }
        surfaces.append(WeakBrowserSurface(surface))
        return surface
    }

    /// Terminal close. Detaching a view to move it does not close its session.
    public func close() {
        guard !closed else { return }
        closed = true
        browserMenu?.close()
        browserMenu = nil
        KelpieBrowserProfile.release(runtimeID)
        NessieConnection.shared.detach(context: serverState.handlerContext)
        serverState.stop()
        serverState.handlerContext.cookieSync?.close()
        serverState.handlerContext.cookieSync = nil
        _ = serverState.scriptPlaybackState.requestAbort()
        serverState.router.retire()
        NetworkTrafficStore.shared.flush()
        for surface in surfaces.compactMap({ $0.value }) {
            surface.tabs.closeAll()
            WindowRegistry.shared.unregister(id: surface.windowID)
        }
        windows.forEach { $0.close(); $0.contentViewController = nil }
        windows = []
        surfaces = []
        regions = []
    }

    func register(region: NSView) {
        guard !closed else { return }
        regions.removeAll { $0.view == nil }
        if !regions.contains(where: { $0.view === region }) { regions.append(WeakBrowserRegion(region)) }
        if !KelpieStorage.standalone {
            if browserMenu == nil { browserMenu = EmbeddedBrowserMenu(session: self) }
            browserMenu?.refresh()
        }
    }

    func containsBrowser(in window: NSWindow) -> Bool { regions.contains { $0.view?.window === window } }

    private func contains(_ event: NSEvent) -> Bool {
        regions.contains { item in
            guard let view = item.view, let window = view.window, event.window === window else { return false }
            if event.type == .keyDown, let responder = window.firstResponder as? NSView {
                return view.bounds.intersects(view.convert(responder.bounds, from: responder))
            }
            return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }
    }

    /// The host may use the controller in any supported AppKit container.
    public func openWindow() {
        let surface = makeSurface(ownsWindowChrome: true)
        let size = ViewportState.persistedShellWindowSize ?? ViewportState.minimumShellSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Kelpie"
        window.minSize = ViewportState.minimumShellSize
        window.contentViewController = surface.makeViewController()
        window.isReleasedWhenClosed = false
        if let origin = ViewportState.persistedShellWindowOrigin,
           ViewportState.windowFrameIsUsable(NSRect(origin: origin, size: size)) {
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
        windows.removeAll { !$0.isVisible }
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
public final class KelpieBrowserSurface: ObservableObject {
    let session: KelpieBrowserSession
    let tabs = TabStore()
    let windowID = UUID().uuidString
    let ownsWindowChrome: Bool

    init(session: KelpieBrowserSession, ownsWindowChrome: Bool) {
        self.session = session
        self.ownsWindowChrome = ownsWindowChrome
    }

    public func makeViewController() -> NSViewController {
        NSHostingController(rootView: KelpieBrowserView(surface: self))
    }
}

@MainActor
public struct KelpieBrowserView: View {
    @StateObject private var surface: KelpieBrowserSurface
    @Environment(\.scenePhase) private var scenePhase

    public init(session: KelpieBrowserSession, ownsWindowChrome: Bool = false) {
        _surface = StateObject(wrappedValue: session.makeSurface(ownsWindowChrome: ownsWindowChrome))
    }

    public init(surface: KelpieBrowserSurface) {
        _surface = StateObject(wrappedValue: surface)
    }

    public var body: some View {
        BrowserView(
            browserState: surface.session.browserState,
            serverState: surface.session.serverState,
            rendererState: surface.session.rendererState,
            viewportState: surface.session.serverState.viewportState,
            tabStore: surface.tabs,
            ownsWindowChrome: surface.ownsWindowChrome,
            windowId: surface.windowID
        )
        .background(BrowserInteractionRegion(session: surface.session))
        .onAppear {
            surface.session.start()
            surface.session.setForeground(scenePhase == .active)
        }
        .onChange(of: scenePhase) { phase in surface.session.setForeground(phase == .active) }
        .frame(minWidth: surface.ownsWindowChrome ? ViewportState.minimumShellSize.width : nil,
               minHeight: surface.ownsWindowChrome ? ViewportState.minimumShellSize.height : nil)
    }
}

@MainActor
private final class WeakBrowserSurface {
    weak var value: KelpieBrowserSurface?
    init(_ value: KelpieBrowserSurface) { self.value = value }
}
