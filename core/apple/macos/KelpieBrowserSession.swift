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

    public init(uoaSession: KelpieUOASession? = nil, port: UInt16 = 8420, localControlEnabled: Bool = true) {
        serverState = ServerState(port: port)
        self.localControlEnabled = localControlEnabled
        if let uoaSession { UOAAccount.shared.useHostSession(uoaSession) }
    }

    public func start() {
        guard !started else { return }
        started = true
        _ = AIState.shared
        serverState.startHTTPServer(rendererState: rendererState, listen: localControlEnabled)
        UOALoginCookies.context = serverState.handlerContext
        NessieConnection.shared.start(context: serverState.handlerContext)
        UOAAccount.shared.restoreSession()
    }

    public func setForeground(_ foreground: Bool) {
        NessieConnection.shared.setForeground(foreground)
    }

    public func makeSurface() -> KelpieBrowserSurface {
        KelpieBrowserSurface(session: self)
    }

    /// The host may use the controller in any supported AppKit container.
    public func openWindow() {
        let surface = makeSurface()
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

    init(session: KelpieBrowserSession) { self.session = session }

    public func makeViewController() -> NSViewController {
        NSHostingController(rootView: KelpieBrowserView(surface: self))
    }
}

@MainActor
public struct KelpieBrowserView: View {
    @StateObject private var surface: KelpieBrowserSurface
    @Environment(\.scenePhase) private var scenePhase

    public init(session: KelpieBrowserSession) {
        _surface = StateObject(wrappedValue: session.makeSurface())
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
            windowId: surface.windowID
        )
        .onAppear {
            surface.session.start()
            surface.session.setForeground(scenePhase == .active)
        }
        .onChange(of: scenePhase) { phase in surface.session.setForeground(phase == .active) }
        .frame(minWidth: ViewportState.minimumShellSize.width, minHeight: ViewportState.minimumShellSize.height)
    }
}
