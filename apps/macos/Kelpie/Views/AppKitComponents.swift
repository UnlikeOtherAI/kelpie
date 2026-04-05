import SwiftUI
import AppKit

// MARK: - AppKit toolbar button (bypasses SwiftUI hit testing / first-responder issues)

struct AppKitToolbarButton: NSViewRepresentable {
    let systemName: String
    let accessibilityID: String
    let accessibilityLabel: String
    var isEnabled: Bool = true
    var isSelected: Bool = false
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> ToolbarButtonView {
        let btn = ToolbarButtonView(systemName: systemName)
        btn.setAccessibilityIdentifier(accessibilityID)
        btn.setAccessibilityLabel(accessibilityLabel)
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.handlePress)
        return btn
    }

    func updateNSView(_ nsView: ToolbarButtonView, context: Context) {
        context.coordinator.action = action
        nsView.isEnabled = isEnabled
        nsView.isButtonSelected = isSelected
        nsView.updateIcon(systemName: systemName)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ToolbarButtonView, context: Context) -> CGSize? {
        CGSize(width: 40, height: 34)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func handlePress() { action() }
    }
}

final class ToolbarButtonView: NSButton {
    private let iconView = NSImageView()
    var isButtonSelected = false { didSet { applyAppearance() } }

    init(systemName: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 40, height: 34))
        setButtonType(.momentaryPushIn)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
        ])

        updateIcon(systemName: systemName)
        applyAppearance()
    }

    func updateIcon(systemName: String) {
        iconView.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        applyAppearance()
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 40, height: 34) }

    override var isHighlighted: Bool { didSet { applyAppearance() } }
    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1.0 : 0.55 } }

    private func applyAppearance() {
        if isHighlighted {
            layer?.backgroundColor = isButtonSelected
                ? NSColor.selectedControlColor.withAlphaComponent(0.75).cgColor
                : NSColor.separatorColor.withAlphaComponent(0.18).cgColor
            iconView.contentTintColor = isButtonSelected ? .white : NSColor.labelColor
        } else if isButtonSelected {
            layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.92).cgColor
            layer?.borderColor = NSColor.selectedControlColor.withAlphaComponent(0.5).cgColor
            iconView.contentTintColor = .white
        } else {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
            iconView.contentTintColor = NSColor.labelColor
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - AppKit segmented strip

struct AppKitSegmentedStrip: NSViewRepresentable {
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
        private var tooltipPanel: NSPanel?
        private var hideWorkItem: DispatchWorkItem?

        init(onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
        }

        fileprivate func showTooltip(_ text: String, for button: SegmentedStripButton) {
            guard let parentWindow = button.window else { return }
            hideWorkItem?.cancel(); hideWorkItem = nil

            // NSPanel child window — always above GPU-composited WebView layers.
            let tv: SegmentedTooltipView
            if let panel = tooltipPanel, panel.parent === parentWindow,
               let existing = panel.contentView as? SegmentedTooltipView {
                tv = existing
            } else {
                tooltipPanel?.close()
                tv = SegmentedTooltipView()
                let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: true)
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.contentView = tv
                parentWindow.addChildWindow(panel, ordered: .above)
                tooltipPanel = panel
            }

            tv.setText(text)
            let size = tv.fittingSize
            let btnOnScreen = parentWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let x = (btnOnScreen.midX - size.width / 2).rounded()
            let y = (btnOnScreen.minY - size.height - 6).rounded()
            tooltipPanel?.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: false)
            tooltipPanel?.alphaValue = 0
            tooltipPanel?.orderFront(nil)
            NSAnimationContext.runAnimationGroup { [weak self] ctx in
                ctx.duration = 0.15; ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self?.tooltipPanel?.animator().alphaValue = 1
            }
        }

        fileprivate func hideTooltip(for button: SegmentedStripButton) {
            let workItem = DispatchWorkItem { [weak self] in
                guard let panel = self?.tooltipPanel else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.15; ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().alphaValue = 0
                }) { panel.orderOut(nil) }
            }
            hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
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
                button.onHoverChange = { [weak self] btn, isHovering in
                    isHovering ? self?.showTooltip(item.accessibilityLabel, for: btn) : self?.hideTooltip(for: btn)
                }
                buttonsByID[item.id] = button
                container.stackView.addArrangedSubview(button)
            }
        }
    }
}

final class SegmentedStripContainerView: NSView {
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

final class SegmentedStripButton: NSButton {
    let itemID: String
    var isSegmentSelected = false
    var onHoverChange: ((SegmentedStripButton, Bool) -> Void)?
    private var trackingAreaRef: NSTrackingArea?
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
        toolTip = nil  // custom hover tooltip handles this
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); onHoverChange?(self, true) }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); onHoverChange?(self, false) }

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
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

final class SegmentedTooltipView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.96).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.42, alpha: 1).cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .medium)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String) { label.stringValue = text; layoutSubtreeIfNeeded() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var fittingSize: NSSize {
        let s = label.fittingSize
        return NSSize(width: s.width + 20, height: max(s.height + 12, 28))
    }
}

// MARK: - AppKit invisible click interceptor
//
// Transparent NSButton overlay — place above a SwiftUI visual in a ZStack or
// via .overlay() to make clicks WebView-first-responder-safe. The NSButton
// participates in hitTest before the responder chain runs, so WebView focus
// cannot block it.

struct AppKitInvisibleButton: NSViewRepresentable {
    let accessibilityID: String
    let accessibilityLabel: String
    var isEnabled: Bool = true
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.imagePosition = .noImage
        button.title = ""
        button.wantsLayer = true
        button.layer?.backgroundColor = .clear
        button.target = context.coordinator
        button.action = #selector(Coordinator.tapped)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.action = action
        nsView.isEnabled = isEnabled
        nsView.setAccessibilityIdentifier(accessibilityID)
        nsView.setAccessibilityLabel(accessibilityLabel)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
