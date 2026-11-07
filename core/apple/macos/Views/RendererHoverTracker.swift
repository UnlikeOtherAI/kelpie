import AppKit

/// Native pointer tracking with a short-lived hit-test expression, never a page content script.
@MainActor
final class RendererHoverTracker: NSObject {
    private weak var container: NSView?
    private weak var renderer: (any RendererEngine)?
    private var trackingArea: NSTrackingArea?
    private var motionMonitor: Any?
    private var pending: Task<Void, Never>?
    private var generation = 0
    private var topInset: CGFloat = 0
    private var onChange: (String) -> Void = { _ in }

    func update(container: NSView, renderer: (any RendererEngine)?, topInset: CGFloat, onChange: @escaping (String) -> Void) {
        if self.renderer !== renderer || self.topInset != topInset {
            generation += 1
            pending?.cancel()
        }
        self.renderer = renderer
        self.topInset = topInset
        self.onChange = onChange
        guard self.container !== container else { return }
        if let trackingArea { self.container?.removeTrackingArea(trackingArea) }
        self.container = container
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        trackingArea = area
        container.addTrackingArea(area)
        if let motionMonitor { NSEvent.removeMonitor(motionMonitor) }
        motionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self, weak container] event in
            guard let container, event.window === container.window else { return event }
            self?.mouseMoved(with: event)
            return event
        }
    }

    @objc func mouseMoved(with event: NSEvent) {
        guard let container, let renderer, !renderer.makeView().isHidden else { clear(); return }
        let point = container.convert(event.locationInWindow, from: nil)
        let x = point.x
        let y = container.bounds.height - point.y - topInset
        guard container.visibleRect.contains(point), y >= 0 else { clear(); return }
        generation += 1
        let request = generation
        pending?.cancel()
        pending = Task { [weak self, weak renderer] in
            do {
                try await Task.sleep(nanoseconds: 30_000_000)
                guard !Task.isCancelled, let renderer else { return }
                let result = try await renderer.evaluateJS(Self.hitTestScript(x: x, y: y))
                guard !Task.isCancelled, let self, self.generation == request else { return }
                self.onChange(result as? String ?? "")
            } catch {
                guard !Task.isCancelled, let self, self.generation == request else { return }
                self.onChange("")
            }
        }
    }

    @objc func mouseExited(with event: NSEvent) { clear() }

    func clear() {
        generation += 1
        pending?.cancel()
        onChange("")
    }

    static func hitTestScript(x: CGFloat, y: CGFloat) -> String {
        """
        (() => {
            let x = \(x), y = \(y), root = document, node = root.elementFromPoint(x, y);
            for (let depth = 0; node && depth < 16; depth++) {
                const anchor = node.closest('a[href], area[href]');
                if (anchor) return anchor.href || '';
                if (node.shadowRoot) {
                    const next = node.shadowRoot.elementFromPoint(x, y);
                    if (next && next !== node) { node = next; continue; }
                }
                if (node.tagName === 'IFRAME') {
                    try {
                        const frame = node.contentDocument, rect = node.getBoundingClientRect();
                        if (!frame) return '';
                        x -= rect.left + node.clientLeft; y -= rect.top + node.clientTop;
                        root = frame; node = root.elementFromPoint(x, y); continue;
                    } catch (_) { return ''; }
                }
                return '';
            }
            return '';
        })()
        """
    }

    func detach() {
        pending?.cancel()
        if let trackingArea { container?.removeTrackingArea(trackingArea) }
        trackingArea = nil
        if let motionMonitor { NSEvent.removeMonitor(motionMonitor) }
        motionMonitor = nil
        container = nil
    }

    deinit {
        pending?.cancel()
        if let motionMonitor { NSEvent.removeMonitor(motionMonitor) }
    }
}
