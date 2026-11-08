import AppKit
import SwiftUI

/// One browser runtime; each surface owns its tabs independently of its host view.
@MainActor
public final class KelpieBrowserSession: ObservableObject {
    let browserState = BrowserState()
    let rendererState = RendererState()
    let serverState: ServerState
    private let localControlEnabled: Bool
    private var started = false
    private var windows: [NSWindow] = []
    private var regions: [WeakBrowserRegion] = []

    public init(uoaSession: KelpieUOASession? = nil, port: UInt16 = 8420, localControlEnabled: Bool = true) {
        serverState = ServerState(port: port)
        self.localControlEnabled = localControlEnabled
        if let uoaSession { UOAAccount.shared.useHostSession(uoaSession) }
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
        guard !started else { return }
        started = true
        _ = AIState.shared
        serverState.startHTTPServer(rendererState: rendererState, listen: localControlEnabled)
        UOALoginCookies.context = serverState.handlerContext
        NessieConnection.shared.acceptsPersonEvent = { [weak self] event in self?.contains(event) == true }
        NessieConnection.shared.start(context: serverState.handlerContext)
        UOAAccount.shared.restoreSession()
    }

    public func setForeground(_ foreground: Bool) {
        NessieConnection.shared.setForeground(foreground)
    }

    public func makeSurface(ownsWindowChrome: Bool = false) -> KelpieBrowserSurface {
        KelpieBrowserSurface(session: self, ownsWindowChrome: ownsWindowChrome)
    }

    func register(region: NSView) {
        regions.removeAll { $0.view == nil }
        if !regions.contains(where: { $0.view === region }) { regions.append(WeakBrowserRegion(region)) }
    }

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
