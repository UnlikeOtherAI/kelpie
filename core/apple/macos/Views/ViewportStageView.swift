import SwiftUI

struct ViewportStageView<Content: View>: View {
    @ObservedObject var viewportState: ViewportState
    let stageScale: Double
    let contentUnderlap: CGFloat
    let showsStageChrome: Bool
    let content: () -> Content

    private let stageColor = Color(nsColor: NSColor(calibratedWhite: 0.17, alpha: 1))
    private let viewportBorderColor = Color(nsColor: NSColor(calibratedWhite: 0.42, alpha: 1))

    init(
        viewportState: ViewportState,
        stageScale: Double,
        contentUnderlap: CGFloat = 0,
        showsStageChrome: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.viewportState = viewportState
        self.stageScale = stageScale
        self.contentUnderlap = contentUnderlap
        self.showsStageChrome = showsStageChrome
        self.content = content
    }

    // Height of the stage-chrome header (summary pill + spacing below it).
    private static var stageChromeHeight: CGFloat { 48 }

    var body: some View {
        GeometryReader { geometry in
            let vp = viewportState.viewportSize
            let staged = viewportState.showsViewportStageChrome
            let chrome = showsStageChrome
            let stageDecorationRadius: CGFloat = chrome ? 16 : 0
            // Scale applies whenever the viewport is staged, even if the header is hidden.
            let scale = staged ? stageScale : 1.0

            // Visual size of the viewport after applying scale.
            let scaledW = (vp.width * scale).rounded(.down)
            let scaledH = (vp.height * scale).rounded(.down)
            let chromeH: CGFloat = chrome ? (Self.stageChromeHeight + 10) : 0

            let canvasSize = CGSize(
                width: max(scaledW, geometry.size.width),
                height: max(scaledH + chromeH, geometry.size.height)
            )

            ZStack {
                backgroundColor

                if !staged {
                    // Full-size browsing needs no outer scroll view or clip. Let the
                    // native renderer paint upward beneath the translucent chrome.
                    content().padding(.top, -contentUnderlap)
                } else if vp.width > 0, vp.height > 0 {
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        ZStack {
                            Color.clear.frame(width: canvasSize.width, height: canvasSize.height)

                            VStack(spacing: chrome ? 10 : 0) {
                                if chrome {
                                    stageChromeHeader(width: scaledW)
                                }

                                // Render content at the logical viewport size, then scale visually.
                                // Negative padding adjusts the layout frame to match the visual size
                                // so the scroll view sees the correct content bounds.
                                content()
                                    .frame(width: vp.width, height: vp.height)
                                    .scaleEffect(scale, anchor: .center)
                                    .padding(.horizontal, -(vp.width * (1 - scale)) / 2)
                                    .padding(.vertical, -(vp.height * (1 - scale)) / 2)
                                    .background(Color.black)
                                    .clipShape(RoundedRectangle(cornerRadius: stageDecorationRadius, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: stageDecorationRadius, style: .continuous)
                                            .stroke(chrome ? viewportBorderColor : .clear, lineWidth: 1)
                                    )
                                    .shadow(color: chrome ? Color.black.opacity(0.22) : .clear, radius: 14, y: 6)
                            }
                        }
                        .frame(width: canvasSize.width, height: canvasSize.height)
                    }
                    .defaultScrollAnchor(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                viewportState.updateStageSize(geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                viewportState.updateStageSize(newSize)
            }
        }
    }

    private var backgroundColor: Color {
        viewportState.showsViewportStageChrome ? stageColor : Color(nsColor: .windowBackgroundColor)
    }

    @ViewBuilder
    private func stageChromeHeader(width: CGFloat) -> some View {
        HStack(spacing: 6) {
            ViewportCloseButton(action: { _ = viewportState.selectFullViewport() })
                .frame(width: 28, height: 28)
                .accessibilityIdentifier("browser.viewport.close")

            Text(viewportState.stageSummaryLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.9))
                .clipShape(Capsule())
                .overlay { Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1) }
                .accessibilityIdentifier("browser.viewport.summary")

            // Balance spacer matching the close button width
            Color.clear.frame(width: 28, height: 28)
        }
        .frame(width: max(width, 80), height: Self.stageChromeHeight)
    }
}

private struct ViewportCloseButton: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> ViewportCloseButtonView {
        let btn = ViewportCloseButtonView()
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.handlePress)
        return btn
    }

    func updateNSView(_ nsView: ViewportCloseButtonView, context: Context) {
        context.coordinator.action = action
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ViewportCloseButtonView, context: Context) -> CGSize? {
        CGSize(width: 28, height: 28)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func handlePress() { action() }
    }
}

private final class ViewportCloseButtonView: NSButton {
    private let iconView = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        setButtonType(.momentaryPushIn)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.9).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer?.borderWidth = 1

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        iconView.contentTintColor = .white
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12)
        ])
    }

    override var isHighlighted: Bool {
        didSet {
            layer?.backgroundColor = isHighlighted
                ? NSColor.white.withAlphaComponent(0.25).cgColor
                : NSColor.black.withAlphaComponent(0.9).cgColor
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 28) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not implemented") }
}
