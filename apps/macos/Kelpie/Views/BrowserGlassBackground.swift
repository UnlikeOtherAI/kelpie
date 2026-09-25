import SwiftUI

/// Native in-window blur samples the live page beneath the chrome.
struct BrowserGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> BrowserGlassEffectView {
        let view = BrowserGlassEffectView()
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: BrowserGlassEffectView, context: Context) {}
}

final class BrowserGlassEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
