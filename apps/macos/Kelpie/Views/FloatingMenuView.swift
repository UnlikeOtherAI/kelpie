import SwiftUI
import AppKit

/// App icon background color — warm peach/orange.
private let kelpieOrange = NSColor(calibratedRed: 244/255, green: 176/255, blue: 120/255, alpha: 1)
/// Richer menu item color — more red/saturated for contrast against the FAB.
private let menuItemOrange = NSColor(calibratedRed: 240/255, green: 148/255, blue: 90/255, alpha: 1)
private enum FloatingMenuLayout {
    static let fabSize: CGFloat = 52
    static let menuItemSize: CGFloat = 52
    static let baseSpreadRadius: CGFloat = 132
    static let minimumItemGap: CGFloat = 12
    static let edgePadding: CGFloat = 16
    static let tooltipSpacing: CGFloat = 10
    static let tooltipEdgeOffset: CGFloat = 12
    static let tooltipFadeDuration: TimeInterval = 0.2

    static func spreadRadius(for itemCount: Int) -> CGFloat {
        guard itemCount > 1 else { return baseSpreadRadius }

        let stepRadians = CGFloat.pi / CGFloat(itemCount - 1)
        let minimumCenterDistance = menuItemSize + minimumItemGap
        let requiredRadius = minimumCenterDistance / (2 * sin(stepRadians / 2))
        return max(baseSpreadRadius, requiredRadius)
    }

    static func fanAngle(index: Int, itemCount: Int, center: Double = 180) -> Angle {
        guard itemCount > 1 else { return .degrees(center) }

        let step = 180.0 / Double(itemCount - 1)
        return .degrees(center - 90 + step * Double(index))
    }
}

/// Floating action button that expands into a fan menu.
/// Uses AppKit-backed buttons so hit testing matches the toolbar behavior.
struct FloatingMenuView: View {
    static let overlayWidth: CGFloat = 220

    @Binding var isOpen: Bool
    let onReload: () -> Void
    let onSafariAuth: () -> Void
    let onSettings: () -> Void
    let onBookmarks: () -> Void
    let onHistory: () -> Void
    let onNetworkInspector: () -> Void
    let onAI: () -> Void
    let onSnapshot3D: () -> Void

    var body: some View {
        GeometryReader { geo in
            AppKitFloatingMenuOverlay(
                size: geo.size,
                isOpen: isOpen,
                actions: actions,
                onToggle: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isOpen.toggle()
                    }
                },
                onSelect: { item in
                    item.action()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isOpen = false
                    }
                },
                onBackgroundTap: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isOpen = false
                    }
                }
            )
        }
    }

    private var actions: [AppKitFloatingMenuOverlay.Item] {
        var items: [AppKitFloatingMenuOverlay.Item] = [
            .init(id: "reload", icon: "arrow.clockwise", accessibilityID: "browser.floating-menu.arrow-clockwise", tooltip: "Reload", action: onReload),
            .init(id: "safari-auth", icon: "safari", accessibilityID: "browser.floating-menu.safari", tooltip: "Safari Auth", action: onSafariAuth),
            .init(id: "bookmarks", icon: "bookmark.fill", accessibilityID: "browser.floating-menu.bookmark-fill", tooltip: "Bookmarks", action: onBookmarks),
            .init(id: "history", icon: "clock.arrow.circlepath", accessibilityID: "browser.floating-menu.clock-arrow-circlepath", tooltip: "History", action: onHistory),
            .init(id: "network-inspector", icon: "antenna.radiowaves.left.and.right", accessibilityID: "browser.floating-menu.antenna-radiowaves-left-and-right", tooltip: "Network", action: onNetworkInspector),
            .init(id: "ai", icon: "brain", accessibilityID: "browser.floating-menu.brain", tooltip: "AI", action: onAI),
            .init(id: "settings", icon: "gear", accessibilityID: "browser.floating-menu.gear", tooltip: "Settings", action: onSettings),
        ]

        if FeatureFlags.is3DInspectorEnabled {
            items.insert(
                .init(
                    id: "snapshot-3d",
                    icon: "cube.transparent",
                    accessibilityID: "browser.floating-menu.cube-transparent",
                    tooltip: "3D Inspector",
                    action: onSnapshot3D
                ),
                at: max(items.count - 1, 0)
            )
        }

        return items
    }
}

private struct AppKitFloatingMenuOverlay: NSViewRepresentable {
    struct Item {
        let id: String
        let icon: String
        let accessibilityID: String
        let tooltip: String
        let action: () -> Void
    }

    let size: CGSize
    let isOpen: Bool
    let actions: [Item]
    let onToggle: () -> Void
    let onSelect: (Item) -> Void
    let onBackgroundTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToggle: onToggle, onSelect: onSelect, onBackgroundTap: onBackgroundTap)
    }

    func makeNSView(context: Context) -> FloatingMenuContainerView {
        let view = FloatingMenuContainerView()
        context.coordinator.install(in: view, items: actions)
        return view
    }

    func updateNSView(_ nsView: FloatingMenuContainerView, context: Context) {
        context.coordinator.onToggle = onToggle
        context.coordinator.onSelect = onSelect
        context.coordinator.onBackgroundTap = onBackgroundTap
        context.coordinator.update(container: nsView, size: size, isOpen: isOpen, items: actions)
    }

    final class Coordinator: NSObject {
        var onToggle: () -> Void
        var onSelect: (Item) -> Void
        var onBackgroundTap: () -> Void

        private weak var container: FloatingMenuContainerView?
        private var itemButtons: [String: FloatingMenuActionButton] = [:]

        init(
            onToggle: @escaping () -> Void,
            onSelect: @escaping (Item) -> Void,
            onBackgroundTap: @escaping () -> Void
        ) {
            self.onToggle = onToggle
            self.onSelect = onSelect
            self.onBackgroundTap = onBackgroundTap
        }

        func install(in container: FloatingMenuContainerView, items: [Item]) {
            self.container = container
            container.onBackgroundTap = { [weak self] in
                self?.onBackgroundTap()
            }

            let toggleButton = FloatingMenuActionButton(
                symbolName: "flame.fill",
                diameter: FloatingMenuLayout.fabSize,
                backgroundColor: kelpieOrange
            )
            toggleButton.toolTip = nil
            toggleButton.hoverText = "Open Menu"
            toggleButton.target = self
            toggleButton.action = #selector(handleToggle)
            toggleButton.setAccessibilityIdentifier("browser.floating-menu.toggle")
            toggleButton.onHoverChange = { [weak container] sourceButton, isHovering in
                guard let container else { return }
                if isHovering {
                    container.showTooltip(sourceButton.hoverText ?? "", for: sourceButton)
                } else {
                    container.hideTooltip(for: sourceButton)
                }
            }
            container.toggleButton = toggleButton
            container.addSubview(toggleButton)

            rebuildItemButtons(in: container, items: items)
        }

        func update(container: FloatingMenuContainerView, size: CGSize, isOpen: Bool, items: [Item]) {
            container.onBackgroundTap = { [weak self] in
                self?.onBackgroundTap()
            }
            let existingIDs = container.itemButtons.map(\.itemID)
            let newIDs = items.map(\.id)
            if existingIDs != newIDs {
                rebuildItemButtons(in: container, items: items)
            }

            let layout = Layout(size: size, itemCount: items.count)
            container.frame = CGRect(origin: .zero, size: size)
            container.updateLayout(layout: layout, isOpen: isOpen, buttons: container.itemButtons)
            container.toggleButton?.toolTip = nil
            container.toggleButton?.hoverText = isOpen ? "Close Menu" : "Open Menu"
            container.toggleButton?.alphaValue = isOpen ? 0.8 : 1.0
            if !isOpen {
                container.hideTooltip()
            }

            for (item, button) in zip(items, container.itemButtons) {
                button.toolTip = nil
                button.setAccessibilityIdentifier(item.accessibilityID)
                button.action = #selector(handleItemPress(_:))
                button.target = self
                button.isEnabled = isOpen
                button.hoverText = item.tooltip
                button.onHoverChange = { [weak container] sourceButton, isHovering in
                    guard let container else { return }
                    if isHovering, isOpen {
                        container.showTooltip(item.tooltip, for: sourceButton)
                    } else {
                        container.hideTooltip(for: sourceButton)
                    }
                }
                itemButtons[item.id] = button
            }
        }

        @objc
        private func handleToggle() {
            onToggle()
        }

        @objc
        private func handleItemPress(_ sender: FloatingMenuActionButton) {
            guard let item = container?.item(for: sender.itemID) else { return }
            onSelect(item)
        }

        private func rebuildItemButtons(in container: FloatingMenuContainerView, items: [Item]) {
            container.itemButtons.forEach { $0.removeFromSuperview() }
            container.itemButtons = []
            itemButtons.removeAll()
            container.itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

            for item in items {
                let button = FloatingMenuActionButton(
                    itemID: item.id,
                    symbolName: item.icon,
                    diameter: FloatingMenuLayout.menuItemSize,
                    backgroundColor: menuItemOrange
                )
                button.setAccessibilityIdentifier(item.accessibilityID)
                button.isHidden = true
                button.alphaValue = 0
                button.isEnabled = false
                container.itemButtons.append(button)
                container.addSubview(button)
                itemButtons[item.id] = button
            }
        }
    }

    fileprivate struct Layout {
        let size: CGSize
        let itemCount: Int

        var fabCenter: CGPoint {
            CGPoint(
                x: size.width - FloatingMenuLayout.edgePadding - FloatingMenuLayout.fabSize / 2,
                y: size.height / 2
            )
        }

        func centerForItem(index: Int) -> CGPoint {
            let angle = FloatingMenuLayout.fanAngle(index: index, itemCount: itemCount)
            let spreadRadius = FloatingMenuLayout.spreadRadius(for: itemCount)
            let rawDx = CGFloat(cos(angle.radians)) * spreadRadius
            let rawDy = CGFloat(sin(angle.radians)) * spreadRadius
            let margin = FloatingMenuLayout.menuItemSize / 2 + FloatingMenuLayout.edgePadding

            let dx = min(max(rawDx, margin - fabCenter.x), size.width - margin - fabCenter.x)
            let dy = min(max(rawDy, margin - fabCenter.y), size.height - margin - fabCenter.y)

            return CGPoint(x: fabCenter.x + dx, y: fabCenter.y + dy)
        }
    }
}

private final class FloatingMenuContainerView: NSView {
    private let animationDuration: TimeInterval = 0.22

    var toggleButton: FloatingMenuActionButton?
    var itemButtons: [FloatingMenuActionButton] = []
    var itemsByID: [String: AppKitFloatingMenuOverlay.Item] = [:]
    var onBackgroundTap: (() -> Void)?
    private var currentIsOpen = false
    private let tooltipView = FloatingMenuTooltipView()
    private weak var hoveredButton: FloatingMenuActionButton?
    private var tooltipHideWorkItem: DispatchWorkItem?
    private var isTooltipVisible = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        tooltipView.isHidden = true
        tooltipView.alphaValue = 0
        addSubview(tooltipView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let toggleButton, !toggleButton.isHidden, toggleButton.frame.contains(point) {
            return self
        }

        if currentIsOpen {
            for button in itemButtons where !button.isHidden && button.alphaValue > 0.01 {
                if button.frame.contains(point) {
                    return self
                }
            }
            return self
        }

        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let toggleButton,
           !toggleButton.isHidden,
           toggleButton.frame.contains(point) {
            toggleButton.performClick(nil)
            return
        }

        if currentIsOpen,
           let button = itemButtons.first(where: { !$0.isHidden && $0.alphaValue > 0.01 && $0.frame.contains(point) }) {
            button.performClick(nil)
            return
        }

        if currentIsOpen {
            onBackgroundTap?()
        } else {
            super.mouseDown(with: event)
        }
    }

    func item(for id: String) -> AppKitFloatingMenuOverlay.Item? {
        itemsByID[id]
    }

    func showTooltip(_ text: String, for button: FloatingMenuActionButton) {
        tooltipHideWorkItem?.cancel()
        tooltipHideWorkItem = nil

        tooltipView.setText(text)
        let frame = tooltipFrame(for: button, size: tooltipView.fittingSize).integral
        if hoveredButton === button, isTooltipVisible, tooltipView.alphaValue >= 0.99 {
            tooltipView.frame = frame
            return
        }

        hoveredButton = button
        tooltipView.frame = frame
        fadeTooltip(visible: true)
    }

    func hideTooltip(for button: FloatingMenuActionButton) {
        guard hoveredButton === button else { return }
        hideTooltip()
    }

    func hideTooltip() {
        let previousButton = hoveredButton
        tooltipHideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self, weak previousButton] in
            guard let self else { return }
            if let previousButton, self.hoveredButton !== previousButton {
                return
            }
            self.hoveredButton = nil
            self.fadeTooltip(visible: false)
        }

        tooltipHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    func updateLayout(layout: AppKitFloatingMenuOverlay.Layout, isOpen: Bool, buttons: [FloatingMenuActionButton]) {
        let fabFrame = rect(center: layout.fabCenter, diameter: FloatingMenuLayout.fabSize)
        toggleButton?.frame = fabFrame

        let targetFrames = buttons.enumerated().map { index, _ in
            rect(
                center: isOpen ? layout.centerForItem(index: index) : layout.fabCenter,
                diameter: FloatingMenuLayout.menuItemSize
            )
        }

        guard currentIsOpen != isOpen else {
            for (button, frame) in zip(buttons, targetFrames) {
                button.frame = frame
                button.alphaValue = isOpen ? 1.0 : 0.0
                button.isHidden = !isOpen
            }
            if let hoveredButton, !tooltipView.isHidden {
                tooltipView.frame = tooltipFrame(for: hoveredButton, size: tooltipView.fittingSize).integral
            }
            return
        }

        if isOpen {
            for button in buttons {
                button.isHidden = false
                button.frame = fabFrame
                button.alphaValue = 0
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for (button, frame) in zip(buttons, targetFrames) {
                    button.animator().setFrameOrigin(frame.origin)
                    button.animator().alphaValue = 1
                }
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for button in buttons {
                    button.animator().setFrameOrigin(fabFrame.origin)
                    button.animator().alphaValue = 0
                }
            } completionHandler: {
                for button in buttons {
                    button.isHidden = true
                    button.frame = fabFrame
                }
                self.hideTooltip()
            }
        }

        currentIsOpen = isOpen
    }

    private func rect(center: CGPoint, diameter: CGFloat) -> CGRect {
        CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
    }

    private func tooltipFrame(for button: FloatingMenuActionButton, size: CGSize) -> CGRect {
        let x = button.frame.minX - size.width - FloatingMenuLayout.tooltipSpacing
        let verticalOffset = tooltipVerticalOffset(for: button)
        let y = button.frame.midY - size.height / 2 + verticalOffset
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func tooltipVerticalOffset(for button: FloatingMenuActionButton) -> CGFloat {
        guard let toggleButton else { return 0 }
        let delta = button.frame.midY - toggleButton.frame.midY
        if delta < -FloatingMenuLayout.menuItemSize {
            return -FloatingMenuLayout.tooltipEdgeOffset
        }
        if delta > FloatingMenuLayout.menuItemSize {
            return FloatingMenuLayout.tooltipEdgeOffset
        }
        return 0
    }

    private func fadeTooltip(visible: Bool) {
        if visible {
            if tooltipView.isHidden {
                tooltipView.alphaValue = 0
                tooltipView.isHidden = false
            }
            isTooltipVisible = true
        } else {
            guard isTooltipVisible || tooltipView.alphaValue > 0.01 else { return }
            isTooltipVisible = false
        }

        tooltipView.layer?.removeAllAnimations()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = FloatingMenuLayout.tooltipFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            tooltipView.animator().alphaValue = visible ? 1 : 0
        } completionHandler: {
            if !visible {
                self.tooltipView.isHidden = true
            }
        }
    }
}

private final class FloatingMenuActionButton: NSButton {
    let itemID: String
    private let iconView: NSImageView
    var hoverText: String?
    var onHoverChange: ((FloatingMenuActionButton, Bool) -> Void)?
    private var trackingAreaRef: NSTrackingArea?

    init(
        itemID: String = "toggle",
        symbolName: String,
        diameter: CGFloat,
        backgroundColor: NSColor
    ) {
        self.itemID = itemID
        self.iconView = NSImageView()
        super.init(frame: .zero)

        setButtonType(.momentaryPushIn)
        isBordered = false
        bezelStyle = .regularSquare
        title = ""
        imagePosition = .noImage
        wantsLayer = true
        layer?.cornerRadius = diameter / 2
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.22).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: symbolName == "flame.fill" ? 22 : 18, weight: .semibold)
        )
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .white
        addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: symbolName == "flame.fill" ? 22 : 18),
            iconView.heightAnchor.constraint(equalToConstant: symbolName == "flame.fill" ? 22 : 18),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange?(self, true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(self, false)
    }
}

private final class FloatingMenuTooltipView: NSView {
    private let textField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.96).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.42, alpha: 1).cgColor

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.textColor = .white
        textField.font = .systemFont(ofSize: 12, weight: .medium)
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setText(_ text: String) {
        textField.stringValue = text
        layoutSubtreeIfNeeded()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var fittingSize: NSSize {
        let labelSize = textField.fittingSize
        return NSSize(width: labelSize.width + 20, height: max(labelSize.height + 12, 28))
    }
}
