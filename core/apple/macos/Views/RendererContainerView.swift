#if !KELPIE_WEBKIT_ONLY
@_implementationOnly import KelpieChromium
#endif
import SwiftUI
import WebKit

/// Wraps the active renderer's NSView in SwiftUI.
struct RendererContainerView: NSViewRepresentable {
    let chromeAppearance: BrowserChromeAppearance
    @ObservedObject var rendererState: RendererState
    @ObservedObject var tabStore: TabStore
    var chromeUnderlap: CGFloat = 0
    var onHoverURL: (String) -> Void = { _ in }
    var onChromeScroll: (Bool) -> Void = { _ in }

    private var displayedRenderer: (any RendererEngine)? {
        tabStore.activeRenderer
    }

    @MainActor
    final class Coordinator {
        weak var attachedRenderer: (any RendererEngine)?
        private var eventMonitor: Any?
        private var scrollMonitor: Any?
        private var passwordClickMonitor: Any?
        let hoverTracker = RendererHoverTracker()
        let chromeSampler = BrowserChromeSampler()
        var chromeUnderlap: CGFloat = 0
        var onChromeScroll: (Bool) -> Void = { _ in }

        /// Installs a local event monitor that resigns the WebView as first responder
        /// whenever the user clicks outside the renderer container. This allows SwiftUI
        /// controls elsewhere in the window (AI panel, resize separator, overlays) to
        /// receive mouse events normally.
        func installEventMonitor(for container: NSView) {
            guard eventMonitor == nil else { return }
            passwordClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .keyUp]) { [weak self, weak container] event in
                guard let renderer = self?.attachedRenderer as? WKWebViewRenderer, let container,
                      let window = container.window, event.window === window, let content = window.contentView else { return event }
                if event.type == .keyUp {
                    if event.keyCode == 48, let responder = window.firstResponder as? NSView, responder.isDescendant(of: renderer.webView) {
                        renderer.websitePasswords.offer(in: renderer.webView, at: nil, explicit: false)
                    }
                    return event
                }
                guard let hit = content.hitTest(content.convert(event.locationInWindow, from: nil)),
                      hit === renderer.webView || hit.isDescendant(of: renderer.webView) else { return event }
                let point = renderer.webView.convert(event.locationInWindow, from: nil)
                renderer.websitePasswords.offer(in: renderer.webView, at: point, explicit: false)
                return event
            }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak container] event in
                guard let container, let window = container.window, event.window === window,
                      window.attachedSheet == nil,
                      container.visibleRect.contains(container.convert(event.locationInWindow, from: nil)),
                      container.bounds.height - container.convert(event.locationInWindow, from: nil).y >= (self?.chromeUnderlap ?? 0),
                      let collapsed = BrowserChromeScroll.collapsed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
                else { return event }
                self?.hoverTracker.clear()
                self?.chromeSampler.sampleAfterScroll()
                self?.onChromeScroll(collapsed)
                return event
            }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak container] event in
                guard let container, let window = container.window, event.window === window else {
                    return event
                }
                let locationInContainer = container.convert(event.locationInWindow, from: nil)
                if !container.bounds.contains(locationInContainer) {
                    if let fr = window.firstResponder {
                        let cls = NSStringFromClass(type(of: fr))
                        if cls.contains("WKWeb") || cls.contains("CrWeb") || cls.contains("CEF") {
                            window.makeFirstResponder(nil)
                        }
                    }
                }
                return event
            }
        }

        deinit {
            if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
            if let monitor = scrollMonitor { NSEvent.removeMonitor(monitor) }
            if let monitor = passwordClickMonitor { NSEvent.removeMonitor(monitor) }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.attachedRenderer?.willDeactivate()
        coordinator.hoverTracker.detach()
        coordinator.chromeSampler.update(webView: nil, onSample: { _ in })
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.onChromeScroll = onChromeScroll
        context.coordinator.chromeUnderlap = chromeUnderlap
        let container = NSView()
        container.wantsLayer = true
        attachActiveRenderer(to: container, coordinator: context.coordinator)
        context.coordinator.installEventMonitor(for: container)
        updateHover(in: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.onChromeScroll = onChromeScroll
        context.coordinator.chromeUnderlap = chromeUnderlap
        attachActiveRenderer(to: container, coordinator: context.coordinator)
        updateHover(in: container, coordinator: context.coordinator)
        let nonCEFCount = container.subviews.filter {
            !NSStringFromClass(type(of: $0)).contains("CEF")
        }.count
        if nonCEFCount > tabStore.tabs.count {
            removeClosedTabViews(from: container)
        }

    }

    private func updateHover(in container: NSView, coordinator: Coordinator) {
        let webView = rendererState.activeEngine == .webkit && tabStore.activeTab?.isStartPage != true
            ? displayedRenderer?.makeView() as? WKWebView : nil
        coordinator.chromeSampler.update(webView: webView, onSample: chromeAppearance.setSample)
        coordinator.hoverTracker.update(
            container: container,
            renderer: displayedRenderer,
            topInset: chromeUnderlap,
            onChange: onHoverURL
        )
    }

    /// Removes subviews that belong to tabs that no longer exist.
    /// CEF views are never removed — only WKWebView subviews are eligible.
    private func removeClosedTabViews(from container: NSView) {
        let activeViews = Set(tabStore.tabs.map { ObjectIdentifier($0.renderer.makeView()) })
        for subview in container.subviews {
            let isCEF = NSStringFromClass(type(of: subview)).contains("CEF")
            guard !isCEF else { continue }
            if !activeViews.contains(ObjectIdentifier(subview)) {
                subview.removeFromSuperview()
            }
        }
    }

    private func attachActiveRenderer(to container: NSView, coordinator: Coordinator) {
        let renderer = displayedRenderer
        let selectionChanged = renderer !== coordinator.attachedRenderer
        if selectionChanged { coordinator.attachedRenderer?.willDeactivate() }
        guard let renderer else {
            container.subviews.forEach { $0.isHidden = true }
            coordinator.attachedRenderer = nil
            return
        }
        let activeView = renderer.makeView()

        if #available(macOS 26.0, *) {
            for tab in tabStore.tabs {
                (tab.renderer.makeView() as? WKWebView)?.obscuredContentInsets = NSEdgeInsets(
                    top: tab.id == tabStore.activeTabID && rendererState.activeEngine == .webkit ? chromeUnderlap : 0,
                    left: 0,
                    bottom: 0,
                    right: 0
                )
            }
        }
        activeView.frame = container.bounds
        activeView.autoresizingMask = [.width, .height]

        // Add the view if it isn't already a subview.
        // Keep dormant CEF views in their original container. Tab retirement
        // removes their CEF-owned child before removing the Swift host view.
        if activeView.superview !== container {
            container.addSubview(activeView)
        }

        // Show the active view, hide all others.
        for subview in container.subviews {
            subview.isHidden = subview !== activeView || tabStore.activeTab?.isStartPage == true
        }

        renderer.didActivate()
        coordinator.attachedRenderer = renderer
    }
}
