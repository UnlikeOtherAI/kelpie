import AppKit
import SwiftUI

/// AppKit-backed pill button — bypasses SwiftUI hit testing so it works even
/// when WKWebView or CEF holds first responder.
struct AIStatusPill: NSViewRepresentable {
    @ObservedObject var aiState: AIState
    let isOpen: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> PillButtonView {
        let btn = PillButtonView()
        btn.setAccessibilityIdentifier("browser.ai.status-pill")
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.handlePress)
        btn.update(aiState: aiState, isOpen: isOpen)
        return btn
    }

    func updateNSView(_ nsView: PillButtonView, context: Context) {
        context.coordinator.action = action
        nsView.update(aiState: aiState, isOpen: isOpen)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PillButtonView, context: Context) -> CGSize? {
        CGSize(width: nsView.preferredWidth, height: 34)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func handlePress() { action() }
    }
}

final class PillButtonView: NSButton {
    private let brainIcon = NSImageView()
    private let eyeIcon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var _activeAndOpen = false

    private(set) var preferredWidth: CGFloat = 40

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 40, height: 34))

        setButtonType(.momentaryPushIn)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .noImage
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5

        brainIcon.translatesAutoresizingMaskIntoConstraints = false
        brainIcon.image = NSImage(systemSymbolName: "brain", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        brainIcon.imageScaling = .scaleProportionallyUpOrDown

        eyeIcon.translatesAutoresizingMaskIntoConstraints = false
        eyeIcon.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        eyeIcon.imageScaling = .scaleProportionallyUpOrDown
        eyeIcon.isHidden = true

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isHidden = true

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        stack.addArrangedSubview(brainIcon)
        stack.addArrangedSubview(eyeIcon)
        stack.addArrangedSubview(nameLabel)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            brainIcon.widthAnchor.constraint(equalToConstant: 14),
            brainIcon.heightAnchor.constraint(equalToConstant: 14),
            eyeIcon.widthAnchor.constraint(equalToConstant: 13),
            eyeIcon.heightAnchor.constraint(equalToConstant: 13)
        ])

        applyColors()
    }

    func update(aiState: AIState, isOpen: Bool) {
        _activeAndOpen = aiState.activeModel != nil && isOpen
        let hasVision = aiState.activeModel?.capabilities.contains("vision") == true

        eyeIcon.isHidden = !hasVision

        if let model = aiState.activeModel {
            nameLabel.stringValue = shortName(for: model.name)
            nameLabel.isHidden = false
        } else {
            nameLabel.isHidden = true
        }

        applyColors()
        alphaValue = aiState.isAvailable ? 1.0 : 0.65

        preferredWidth = computePreferredWidth()
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: 34)
    }

    override var isHighlighted: Bool {
        didSet { applyColors() }
    }

    private func applyColors() {
        if isHighlighted {
            layer?.backgroundColor = _activeAndOpen
                ? NSColor.controlAccentColor.withAlphaComponent(0.70).cgColor
                : NSColor.separatorColor.withAlphaComponent(0.15).cgColor
        } else if _activeAndOpen {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.95).cgColor
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        } else {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        }
        let iconColor: NSColor = _activeAndOpen ? .white : NSColor.labelColor
        brainIcon.contentTintColor = iconColor
        eyeIcon.contentTintColor = iconColor
        nameLabel.textColor = iconColor
    }

    private func computePreferredWidth() -> CGFloat {
        var width: CGFloat = 10 + 14 + 10  // left pad + brain + right pad
        if !eyeIcon.isHidden { width += 5 + 13 }
        if !nameLabel.isHidden, let font = nameLabel.font {
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let textWidth = (nameLabel.stringValue as NSString).size(withAttributes: attrs).width
            width += 5 + ceil(textWidth)
        }
        return width
    }

    private func shortName(for name: String) -> String {
        name.replacingOccurrences(of: " E2B", with: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not implemented") }
}
