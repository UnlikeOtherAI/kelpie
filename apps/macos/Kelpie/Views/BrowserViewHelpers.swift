import SwiftUI

struct WindowChromeBridge: NSViewRepresentable {
    let title: String
    let minimumWindowSize: NSSize
    let resolutionLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        PassThroughNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.minSize = minimumWindowSize
            window.titleVisibility = .visible
            context.coordinator.attachWindowIfNeeded(window, minimumWindowSize: minimumWindowSize)

            if window.frame.width < minimumWindowSize.width || window.frame.height < minimumWindowSize.height {
                var frame = window.frame
                let targetWidth = max(frame.width, minimumWindowSize.width)
                let targetHeight = max(frame.height, minimumWindowSize.height)
                let widthDelta = targetWidth - frame.width

                frame.size.width = targetWidth
                frame.size.height = targetHeight
                frame.origin.x -= widthDelta / 2
                window.setFrame(frame, display: true)
            }

            if window.title != title {
                window.title = title
            }

            context.coordinator.attachAccessoryIfNeeded(to: window)
            context.coordinator.updateResolutionLabel(resolutionLabel)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var observedWindow: NSWindow?
        private weak var accessoryWindow: NSWindow?
        private var resizeObserver: NSObjectProtocol?
        private let accessoryController = ResolutionTitlebarAccessoryController()

        deinit {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
        }

        func attachWindowIfNeeded(_ window: NSWindow, minimumWindowSize: NSSize) {
            guard observedWindow !== window else { return }

            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }

            observedWindow = window
            restoreWindowSizeIfAvailable(window, minimumWindowSize: minimumWindowSize)
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { _ in
                guard !window.styleMask.contains(.fullScreen) else { return }
                let contentSize = window.contentRect(forFrameRect: window.frame).size
                Task { @MainActor in
                    ViewportState.persistShellWindowSize(contentSize)
                }
            }
        }

        func attachAccessoryIfNeeded(to window: NSWindow) {
            guard accessoryWindow !== window else { return }

            if accessoryController.parent == nil {
                accessoryController.layoutAttribute = .right
                window.addTitlebarAccessoryViewController(accessoryController)
            }

            accessoryWindow = window
        }

        func updateResolutionLabel(_ label: String) {
            accessoryController.setLabel(label)
        }

        private func restoreWindowSizeIfAvailable(_ window: NSWindow, minimumWindowSize: NSSize) {
            guard let savedSize = ViewportState.persistedShellWindowSize else { return }

            let targetSize = NSSize(
                width: max(savedSize.width, minimumWindowSize.width),
                height: max(savedSize.height, minimumWindowSize.height)
            )

            guard !sizesMatch(window.contentRect(forFrameRect: window.frame).size, targetSize) else { return }

            window.setContentSize(targetSize)
        }

        private func sizesMatch(_ lhs: NSSize, _ rhs: NSSize) -> Bool {
            abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
        }
    }
}

private final class PassThroughNSView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

struct FloatingProgressPill: View {
    let progress: Double

    var body: some View {
        VStack {
            Spacer()
            GeometryReader { geometry in
                let pillWidth = geometry.size.width * 0.7

                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.45))
                    .frame(width: pillWidth, height: 6)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor)
                            .frame(
                                width: pillWidth * max(progress, 0.02),
                                height: 6
                            ),
                        alignment: .leading
                    )
                    .clipShape(Capsule(style: .continuous))
                    .frame(width: geometry.size.width)
            }
            .frame(height: 6)
            .padding(.bottom, 44)
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: progress)
    }
}

struct WindowBlurOverlay: NSViewRepresentable {
    let opacity: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .withinWindow
        view.state = .active
        view.alphaValue = opacity
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.alphaValue = opacity
    }
}

// MARK: - AppKit-backed resize handle (bypasses WebView first-responder hit-test issue)

struct AppKitResizeHandle: NSViewRepresentable {
    @Binding var panelWidth: CGFloat
    let onDragEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(binding: $panelWidth, onDragEnd: onDragEnd) }

    func makeNSView(context: Context) -> ResizeHandleView {
        let view = ResizeHandleView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ResizeHandleView, context: Context) {
        context.coordinator.onDragEnd = onDragEnd
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ResizeHandleView, context: Context) -> CGSize? {
        CGSize(width: 6, height: proposal.height ?? 0)
    }

    final class Coordinator: NSObject {
        private var binding: Binding<CGFloat>
        var onDragEnd: () -> Void
        var dragStartWidth: CGFloat?
        var dragStartX: CGFloat?

        var panelWidth: CGFloat {
            get { binding.wrappedValue }
            set { binding.wrappedValue = newValue }
        }

        init(binding: Binding<CGFloat>, onDragEnd: @escaping () -> Void) {
            self.binding = binding
            self.onDragEnd = onDragEnd
        }
    }
}

final class ResizeHandleView: NSView {
    weak var coordinator: AppKitResizeHandle.Coordinator?
    private var trackingArea: NSTrackingArea?
    private let bar = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.separatorColor.cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.widthAnchor.constraint(equalToConstant: 1),
            bar.centerXAnchor.constraint(equalTo: centerXAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { NSCursor.resizeLeftRight.push() }
    override func mouseExited(with event: NSEvent) { NSCursor.pop() }

    override func mouseDown(with event: NSEvent) {
        guard let coord = coordinator else { return }
        coord.dragStartWidth = coord.panelWidth
        coord.dragStartX = event.locationInWindow.x
        NSCursor.resizeLeftRight.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let coord = coordinator,
              let startWidth = coord.dragStartWidth,
              let startX = coord.dragStartX else { return }
        let dx = startX - event.locationInWindow.x
        let newWidth = min(max(startWidth + dx, 200), 500)
        coord.panelWidth = newWidth
    }

    override func mouseUp(with event: NSEvent) {
        coordinator?.dragStartWidth = nil
        coordinator?.dragStartX = nil
        coordinator?.onDragEnd()
        NSCursor.pop()
    }

    override var acceptsFirstResponder: Bool { true }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not implemented") }
}
