import SwiftUI
import AppKit

/// URL bar with navigation buttons, URL field, renderer toggle, and device size selector.
/// Stacks selectors on a second row when window is narrow (phone portrait).
struct URLBarView: View {
    private static let toolbarButtonSize = CGSize(width: 40, height: 34)

    @ObservedObject var browserState: BrowserState
    @ObservedObject var rendererState: RendererState
    @ObservedObject var viewportState: ViewportState
    let onNavigate: (String) -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let onReload: () -> Void
    let onSwitchRenderer: (RendererState.Engine) -> Void

    @State private var urlText: String = ""
    @State private var isNarrow = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                navButton(
                    systemName: "chevron.left",
                    isEnabled: browserState.canGoBack,
                    accessibilityID: "browser.nav.back",
                    accessibilityLabel: "Back",
                    action: onBack
                )

                navButton(
                    systemName: "chevron.right",
                    isEnabled: browserState.canGoForward,
                    accessibilityID: "browser.nav.forward",
                    accessibilityLabel: "Forward",
                    action: onForward
                )

                navButton(
                    systemName: "arrow.clockwise",
                    accessibilityID: "browser.nav.reload",
                    accessibilityLabel: "Reload",
                    action: onReload
                )

                addressField

                if !isNarrow {
                    selectorsRow
                }
            }

            if isNarrow {
                selectorsRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GeometryReader { geo in
            Color.clear.onAppear {
                isNarrow = geo.size.width < 600
            }
            .onChange(of: geo.size.width) { _, w in
                isNarrow = w < 600
            }
        })
        .onAppear {
            urlText = browserState.currentURL
        }
        .onChange(of: browserState.currentURL) { _, newURL in
            urlText = newURL
        }
    }

    @ViewBuilder
    private var selectorsRow: some View {
        HStack(spacing: 8) {
            rendererSwitch
                .disabled(rendererState.isSwitching)

            presetSwitch
        }
    }

    @ViewBuilder
    private var addressField: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search or enter website name", text: $urlText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1)
                .onSubmit { navigate() }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .accessibilityIdentifier("browser.address")
    }

    @ViewBuilder
    private var rendererSwitch: some View {
        AppKitSegmentedStrip(
            items: [
                AppKitSegmentedStrip.Item(
                    id: RendererState.Engine.webkit.rawValue,
                    imageName: "SafariLogo",
                    accessibilityID: "browser.renderer.webkit",
                    accessibilityLabel: "Safari renderer",
                    width: 54,
                    iconSize: 16
                ),
                AppKitSegmentedStrip.Item(
                    id: RendererState.Engine.chromium.rawValue,
                    imageName: "ChromeLogo",
                    accessibilityID: "browser.renderer.chromium",
                    accessibilityLabel: "Chromium renderer",
                    width: 54,
                    iconSize: 16
                ),
                AppKitSegmentedStrip.Item(
                    id: RendererState.Engine.gecko.rawValue,
                    imageName: "FirefoxLogo",
                    accessibilityID: "browser.renderer.gecko",
                    accessibilityLabel: "Firefox renderer",
                    width: 54,
                    iconSize: 16
                ),
            ],
            selectedID: rendererState.activeEngine.rawValue,
            accessibilityID: "browser.renderer.switch",
            isEnabled: !rendererState.isSwitching,
            onSelect: { selectedID in
                guard let engine = RendererState.Engine(rawValue: selectedID) else { return }
                onSwitchRenderer(engine)
            }
        )
        .frame(width: 174, height: 34)
    }

    @ViewBuilder
    private var presetSwitch: some View {
        AppKitSegmentedStrip(
            items: DevicePreset.allCases.map { preset in
                AppKitSegmentedStrip.Item(
                    id: preset.rawValue,
                    systemImageName: preset.icon,
                    accessibilityID: "browser.preset.\(preset.rawValue.replacingOccurrences(of: " ", with: "-").lowercased())",
                    accessibilityLabel: preset.rawValue,
                    width: 44,
                    iconSize: 12
                )
            },
            selectedID: viewportState.selectedPreset.rawValue,
            accessibilityID: "browser.preset.switch",
            isEnabled: true,
            onSelect: { selectedID in
                guard let preset = DevicePreset(rawValue: selectedID) else { return }
                viewportState.selectPreset(preset)
            }
        )
        .frame(width: 290, height: 34)
    }

    @ViewBuilder
    private func navButton(
        systemName: String,
        isEnabled: Bool = true,
        accessibilityID: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )

                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(
                width: Self.toolbarButtonSize.width,
                height: Self.toolbarButtonSize.height
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.55)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(accessibilityLabel)
    }

    private func navigate() {
        var url = urlText.trimmingCharacters(in: .whitespaces)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://\(url)"
        }
        onNavigate(url)
    }
}

private struct AppKitSegmentedStrip: NSViewRepresentable {
    struct Item: Equatable {
        let id: String
        var title: String? = nil
        var imageName: String? = nil
        var systemImageName: String? = nil
        let accessibilityID: String
        let accessibilityLabel: String
        let width: CGFloat
        let iconSize: CGFloat
    }

    let items: [Item]
    let selectedID: String
    let accessibilityID: String
    let isEnabled: Bool
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> SegmentedStripContainerView {
        let container = SegmentedStripContainerView()
        container.setAccessibilityIdentifier(accessibilityID)
        context.coordinator.install(in: container, items: items)
        return container
    }

    func updateNSView(_ nsView: SegmentedStripContainerView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.update(container: nsView, items: items, selectedID: selectedID, isEnabled: isEnabled)
    }

    final class Coordinator: NSObject {
        var onSelect: (String) -> Void
        private weak var container: SegmentedStripContainerView?
        private var buttonsByID: [String: SegmentedStripButton] = [:]

        init(onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
        }

        func install(in container: SegmentedStripContainerView, items: [Item]) {
            self.container = container
            rebuildButtons(in: container, items: items)
        }

        func update(container: SegmentedStripContainerView, items: [Item], selectedID: String, isEnabled: Bool) {
            let existingIDs = container.stackView.arrangedSubviews.compactMap { ($0 as? SegmentedStripButton)?.itemID }
            let newIDs = items.map(\.id)
            if existingIDs != newIDs {
                rebuildButtons(in: container, items: items)
            }

            for item in items {
                guard let button = buttonsByID[item.id] else { continue }
                button.isEnabled = isEnabled
                button.isSegmentSelected = item.id == selectedID
                button.updateAppearance()
            }
        }

        @objc
        private func handlePress(_ sender: SegmentedStripButton) {
            onSelect(sender.itemID)
        }

        private func rebuildButtons(in container: SegmentedStripContainerView, items: [Item]) {
            buttonsByID.removeAll()
            container.stackView.arrangedSubviews.forEach { view in
                container.stackView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }

            for item in items {
                let button = SegmentedStripButton(item: item)
                button.target = self
                button.action = #selector(handlePress(_:))
                buttonsByID[item.id] = button
                container.stackView.addArrangedSubview(button)
            }
        }
    }
}

private final class SegmentedStripContainerView: NSView {
    let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        layer?.borderWidth = 0.5
        layer?.cornerRadius = 15

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.spacing = 4
        stackView.alignment = .centerY
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class SegmentedStripButton: NSButton {
    let itemID: String
    var isSegmentSelected = false
    private let usesSymbolTint: Bool
    private let iconView: NSImageView?

    init(item: AppKitSegmentedStrip.Item) {
        self.itemID = item.id
        self.usesSymbolTint = item.systemImageName != nil

        if let imageName = item.imageName {
            let view = NSImageView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.image = NSImage(named: imageName)
            view.imageScaling = .scaleProportionallyUpOrDown
            view.symbolConfiguration = nil
            self.iconView = view
        } else if let systemImageName = item.systemImageName {
            let view = NSImageView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.image = NSImage(
                systemSymbolName: systemImageName,
                accessibilityDescription: item.accessibilityLabel
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: item.iconSize, weight: .regular)
            )
            view.imageScaling = .scaleProportionallyUpOrDown
            view.contentTintColor = .labelColor
            self.iconView = view
        } else {
            self.iconView = nil
        }

        super.init(frame: .zero)

        setButtonType(.momentaryPushIn)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        title = ""
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.masksToBounds = true
        toolTip = item.accessibilityLabel
        setAccessibilityIdentifier(item.accessibilityID)
        setAccessibilityLabel(item.accessibilityLabel)

        if let iconView {
            addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: item.iconSize),
                iconView.heightAnchor.constraint(equalToConstant: item.iconSize),
            ])
        } else {
            title = item.title ?? ""
            font = .systemFont(ofSize: 12, weight: .semibold)
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: item.width),
            heightAnchor.constraint(equalToConstant: 30),
        ])

        updateAppearance()
    }

    override var isHighlighted: Bool {
        didSet {
            updateAppearance()
        }
    }

    override var isEnabled: Bool {
        didSet {
            updateAppearance()
        }
    }

    func updateAppearance() {
        let selectedBackground = NSColor.selectedControlColor.withAlphaComponent(0.92)
        let pressedBackground = isSegmentSelected
            ? NSColor.selectedControlColor.withAlphaComponent(0.75)
            : NSColor.separatorColor.withAlphaComponent(0.12)

        layer?.backgroundColor = (isHighlighted ? pressedBackground : (isSegmentSelected ? selectedBackground : .clear)).cgColor

        if usesSymbolTint {
            iconView?.contentTintColor = isSegmentSelected ? .white : NSColor.labelColor.withAlphaComponent(0.82)
        } else if iconView == nil {
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: isSegmentSelected ? NSColor.white : NSColor.labelColor.withAlphaComponent(0.82),
                ]
            )
        }

        alphaValue = isEnabled ? 1.0 : 0.5
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
