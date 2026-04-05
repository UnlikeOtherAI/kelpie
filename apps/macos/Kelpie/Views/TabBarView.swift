import AppKit
import Combine
import SwiftUI

// MARK: - Public NSViewRepresentable

struct TabBarView: NSViewRepresentable {
    @ObservedObject var tabStore: TabStore
    let onNewTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onSelectTab: (UUID) -> Void

    func makeCoordinator() -> TabBarCoordinator {
        TabBarCoordinator(onNewTab: onNewTab, onCloseTab: onCloseTab, onSelectTab: onSelectTab)
    }

    func makeNSView(context: Context) -> TabBarContainerView {
        let container = TabBarContainerView()
        container.addButton.target = context.coordinator
        container.addButton.action = #selector(TabBarCoordinator.handleAddTab)
        context.coordinator.container = container
        context.coordinator.update(in: container, tabStore: tabStore)
        let coordinator = context.coordinator
        container.onFrameChange = { [weak coordinator, weak container] _ in
            guard let coordinator, let container, let store = coordinator.currentTabStore else { return }
            coordinator.relayout(in: container, tabStore: store)
        }
        return container
    }

    func updateNSView(_ nsView: TabBarContainerView, context: Context) {
        context.coordinator.onNewTab = onNewTab
        context.coordinator.onCloseTab = onCloseTab
        context.coordinator.onSelectTab = onSelectTab
        context.coordinator.update(in: nsView, tabStore: tabStore)
    }
}

// MARK: - Coordinator

@MainActor
final class TabBarCoordinator: NSObject {
    var onNewTab: () -> Void
    var onCloseTab: (UUID) -> Void
    var onSelectTab: (UUID) -> Void

    weak var container: TabBarContainerView?
    private var pillsByID: [UUID: TabPillView] = [:]
    var currentTabStore: TabStore?

    init(onNewTab: @escaping () -> Void, onCloseTab: @escaping (UUID) -> Void, onSelectTab: @escaping (UUID) -> Void) {
        self.onNewTab = onNewTab
        self.onCloseTab = onCloseTab
        self.onSelectTab = onSelectTab
    }

    @objc func handleAddTab() {
        onNewTab()
    }

    func update(in container: TabBarContainerView, tabStore: TabStore) {
        currentTabStore = tabStore

        let currentIDs = tabStore.tabs.map(\.id)
        let existingIDs = Set(pillsByID.keys)
        let newIDs = Set(currentIDs)

        // Remove pills for closed tabs
        for id in existingIDs where !newIDs.contains(id) {
            pillsByID[id]?.removeFromSuperview()
            pillsByID.removeValue(forKey: id)
        }

        // Add pills for new tabs
        for tab in tabStore.tabs where pillsByID[tab.id] == nil {
            let pill = TabPillView(tab: tab)
            pill.onSelect = { [weak self] id in self?.onSelectTab(id) }
            pill.onClose = { [weak self] id in self?.onCloseTab(id) }
            container.scrollContent.addSubview(pill)
            pillsByID[tab.id] = pill
        }

        relayout(in: container, tabStore: tabStore)
    }

    func relayout(in container: TabBarContainerView, tabStore: TabStore) {
        guard !tabStore.tabs.isEmpty else { return }
        guard container.bounds.width > 0 else { return }

        let addButtonWidth: CGFloat = 28
        let rightMargin: CGFloat = 6
        let leftInset: CGFloat = 4
        let height: CGFloat = container.bounds.height > 0 ? container.bounds.height - 4 : 34
        let avail = container.bounds.width - addButtonWidth - rightMargin - leftInset

        let tabCount = tabStore.tabs.count
        let tabW: CGFloat
        if tabCount > 0 && avail > 0 {
            let ideal = avail / CGFloat(tabCount)
            tabW = min(max(ideal, 80), 200)
        } else {
            tabW = 160
        }

        let totalTabsW = tabW * CGFloat(tabCount)
        let needsScroll = totalTabsW > avail + 1

        container.scrollView.hasHorizontalScroller = needsScroll

        // Resize scroll content to fit pills
        let contentW = max(totalTabsW + leftInset, container.bounds.width - addButtonWidth - rightMargin)
        container.scrollContent.frame = CGRect(x: 0, y: 0, width: contentW, height: container.bounds.height)

        // Position pills in tab order
        for (idx, tab) in tabStore.tabs.enumerated() {
            guard let pill = pillsByID[tab.id] else { continue }
            let x = leftInset + CGFloat(idx) * tabW
            let y: CGFloat = 2
            pill.frame = CGRect(x: x, y: y, width: tabW - 2, height: height)
            pill.setActive(tab.id == tabStore.activeTabID)
        }

        // Position add button
        let addX = container.bounds.width - addButtonWidth - rightMargin
        container.addButton.frame = CGRect(x: addX, y: (container.bounds.height - 26) / 2, width: addButtonWidth, height: 26)

        // Slide indicator to active tab
        if let activeID = tabStore.activeTabID, let activePill = pillsByID[activeID] {
            container.moveIndicator(to: activePill.frame, in: container.scrollContent)

            // Scroll active pill into view with animation
            if needsScroll {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    container.scrollView.contentView.animator().scrollToVisible(activePill.frame)
                }
            }
        }
    }
}

// MARK: - TabBarContainerView

final class TabBarContainerView: NSView {
    let scrollView = NSScrollView()
    let scrollContent = NSView()
    let addButton = NSButton()

    // Indicator layer lives on the scrollContent's layer, behind pills.
    private(set) var indicatorLayer = CAShapeLayer()

    var onFrameChange: ((CGRect) -> Void)?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        // Bottom border
        let border = CALayer()
        border.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        border.autoresizingMask = [.layerWidthSizable, .layerMinYMargin]
        border.frame = CGRect(x: 0, y: frame.height - 1, width: frame.width, height: 1)
        layer?.addSublayer(border)

        // Scroll view — no vertical scroller, clipping
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        scrollContent.wantsLayer = true
        scrollView.documentView = scrollContent

        // Indicator layer — behind pills
        indicatorLayer.fillColor = NSColor.selectedControlColor.withAlphaComponent(0.18).cgColor
        indicatorLayer.strokeColor = NSColor.selectedControlColor.withAlphaComponent(0.35).cgColor
        indicatorLayer.lineWidth = 1
        indicatorLayer.frame = scrollContent.bounds
        scrollContent.layer?.addSublayer(indicatorLayer)

        // Add button (+)
        addButton.isBordered = false
        addButton.setButtonType(.momentaryPushIn)
        addButton.imagePosition = .imageOnly
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        addButton.contentTintColor = NSColor.secondaryLabelColor
        addButton.wantsLayer = true
        addButton.layer?.cornerRadius = 5
        addButton.setAccessibilityIdentifier("browser.tabs.add")
        addSubview(addButton)

        // Constrain scroll view to fill minus add button
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(28 + 6)),
        ])
    }

    override func layout() {
        super.layout()
        onFrameChange?(frame)
    }

    func moveIndicator(to pillFrame: CGRect, in contentView: NSView) {
        let inset: CGFloat = 2
        let rect = pillFrame.insetBy(dx: inset, dy: inset)
        let newPath = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)

        if indicatorLayer.path == nil {
            // First placement — no animation
            indicatorLayer.frame = contentView.bounds
            indicatorLayer.path = newPath
        } else {
            indicatorLayer.frame = contentView.bounds
            let anim = CABasicAnimation(keyPath: "path")
            anim.fromValue = indicatorLayer.presentation()?.path ?? indicatorLayer.path
            anim.toValue = newPath
            anim.duration = 0.22
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            indicatorLayer.add(anim, forKey: "indicatorSlide")
            indicatorLayer.path = newPath
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - TabPillView

final class TabPillView: NSView {
    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?

    private let tab: Tab
    private let letterAvatar = LetterAvatarView()
    private let faviconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var cancellables = Set<AnyCancellable>()

    override var isFlipped: Bool { true }

    init(tab: Tab) {
        self.tab = tab
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        // Letter avatar
        letterAvatar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(letterAvatar)

        // Favicon image view (hidden until favicon is set)
        faviconView.translatesAutoresizingMaskIntoConstraints = false
        faviconView.imageScaling = .scaleProportionallyUpOrDown
        faviconView.isHidden = true
        addSubview(faviconView)

        // Title
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.isBordered = false
        titleField.isEditable = false
        titleField.backgroundColor = .clear
        titleField.font = .systemFont(ofSize: 12, weight: .regular)
        titleField.textColor = NSColor.labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        addSubview(titleField)

        // Close button — NSButton handles its own target/action, mouseDown routing is below
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.setButtonType(.momentaryPushIn)
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .bold))
        closeButton.contentTintColor = NSColor.secondaryLabelColor
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 4
        closeButton.setAccessibilityIdentifier("browser.tabs.close")
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            // Letter avatar / favicon — left side, 14pt square
            letterAvatar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            letterAvatar.centerYAnchor.constraint(equalTo: centerYAnchor),
            letterAvatar.widthAnchor.constraint(equalToConstant: 14),
            letterAvatar.heightAnchor.constraint(equalToConstant: 14),

            faviconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            faviconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            faviconView.widthAnchor.constraint(equalToConstant: 14),
            faviconView.heightAnchor.constraint(equalToConstant: 14),

            // Close button — right side, 16pt square
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),

            // Title — fills the middle
            titleField.leadingAnchor.constraint(equalTo: letterAvatar.trailingAnchor, constant: 5),
            titleField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Subscribe to tab changes via Combine (NOT KVO on @Published)
        tab.$title
            .sink { [weak self] _ in self?.refreshContent() }
            .store(in: &cancellables)

        tab.$favicon
            .sink { [weak self] _ in self?.refreshContent() }
            .store(in: &cancellables)

        refreshContent()
    }

    func setActive(_ active: Bool) {
        // Visual distinction for active vs inactive pills
        layer?.backgroundColor = active
            ? NSColor.selectedControlColor.withAlphaComponent(0.08).cgColor
            : NSColor.clear.cgColor
        titleField.textColor = active ? NSColor.labelColor : NSColor.secondaryLabelColor
    }

    private func refreshContent() {
        titleField.stringValue = tab.title

        if let favicon = tab.favicon {
            faviconView.image = favicon
            faviconView.isHidden = false
            letterAvatar.isHidden = true
        } else {
            faviconView.isHidden = true
            letterAvatar.isHidden = false
            let domain = URL(string: tab.currentURL)?.host ?? ""
            letterAvatar.configure(domain: domain)
        }
    }

    // Route mouseDown: pill select unless click is inside close button
    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if let hit = hitTest(localPoint), hit === closeButton || hit.isDescendant(of: closeButton) {
            closeButton.mouseDown(with: event)
        } else {
            onSelect?(tab.id)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if let hit = hitTest(localPoint), hit === closeButton || hit.isDescendant(of: closeButton) {
            closeButton.mouseUp(with: event)
        } else {
            super.mouseUp(with: event)
        }
    }

    @objc private func handleClose() {
        onClose?(tab.id)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - LetterAvatarView

final class LetterAvatarView: NSView {
    private let label = NSTextField(labelWithString: "")

    // 6-color palette — hue values chosen for good contrast on both light/dark
    private static let palette: [NSColor] = [
        NSColor(calibratedHue: 0.60, saturation: 0.55, brightness: 0.75, alpha: 1), // indigo
        NSColor(calibratedHue: 0.33, saturation: 0.50, brightness: 0.65, alpha: 1), // green
        NSColor(calibratedHue: 0.07, saturation: 0.60, brightness: 0.80, alpha: 1), // orange
        NSColor(calibratedHue: 0.87, saturation: 0.50, brightness: 0.75, alpha: 1), // purple
        NSColor(calibratedHue: 0.54, saturation: 0.55, brightness: 0.72, alpha: 1), // teal
        NSColor(calibratedHue: 0.97, saturation: 0.55, brightness: 0.78, alpha: 1), // rose
    ]

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.masksToBounds = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.isBordered = false
        label.isEditable = false
        label.backgroundColor = .clear
        label.textColor = .white
        label.alignment = .center
        label.font = .systemFont(ofSize: 9, weight: .bold)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(domain: String) {
        let letter: String
        if let first = domain.first(where: { $0.isLetter }) {
            letter = String(first).uppercased()
        } else {
            letter = "?"
        }

        label.stringValue = letter

        // Deterministic color from domain hash
        let hash = abs(domain.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
        let color = LetterAvatarView.palette[hash % LetterAvatarView.palette.count]
        layer?.backgroundColor = color.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }
}
