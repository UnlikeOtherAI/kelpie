import AppKit
import SwiftUI

@MainActor
final class WeakBrowserRegion {
    weak var view: NSView?
    init(_ view: NSView) { self.view = view }
}

private final class BrowserRegionView: NSView {
    weak var session: KelpieBrowserSession?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        session?.register(region: self)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Identifies browser input without intercepting any event.
struct BrowserInteractionRegion: NSViewRepresentable {
    let session: KelpieBrowserSession

    func makeNSView(context: Context) -> NSView {
        let view = BrowserRegionView(frame: .zero)
        view.session = session
        session.register(region: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        session.register(region: nsView)
    }
}
