import SwiftUI

/// Place tabs in the native titlebar, avoiding content scroll-view clipping beneath it.
/// The existing window controls remain native and sit beside this accessory.
final class BrowserTabTitlebarController: NSTitlebarAccessoryViewController {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var showsTabs = true

    override func loadView() {
        view = hostingView
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 32)
    }

    func update(_ content: AnyView, visible: Bool, colorScheme: ColorScheme, width: CGFloat) {
        showsTabs = visible
        // Match the content chrome rather than the titlebar's automatic vibrancy appearance.
        hostingView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        hostingView.rootView = AnyView(content.environment(\.colorScheme, colorScheme))
        isHidden = !visible
        fullScreenMinHeight = visible ? 32 : 0
        resize(width: width)
    }

    func resize(width: CGFloat) {
        view.setFrameSize(NSSize(width: max(0, width), height: showsTabs ? 32 : 0))
    }
}
