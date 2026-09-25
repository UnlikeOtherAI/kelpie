import SwiftUI

/// Native in-window blur samples the live page beneath the chrome.
struct BrowserGlassBackground: NSViewRepresentable {
    @ObservedObject var appearance: BrowserChromeAppearance

    func makeNSView(context: Context) -> BrowserGlassEffectView {
        let view = BrowserGlassEffectView()
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: BrowserGlassEffectView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        nsView.tintLayer.backgroundColor = appearance.palette.background.color.withAlphaComponent(0.92).cgColor
        CATransaction.commit()
    }
}

final class BrowserGlassEffectView: NSVisualEffectView {
    let tintLayer = CALayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(tintLayer)
    }
    override func layout() {
        super.layout()
        tintLayer.frame = bounds
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
