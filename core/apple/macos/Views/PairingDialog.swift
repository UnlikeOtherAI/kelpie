import SwiftUI
import AppKit

/// Modal sheet shown when an unauthenticated client requests pairing.
/// Hosted by `BrowserView` and bound to the shared `PairApprovalCoordinator`.
///
/// Deny is the default; allowing a computer grants persistent signing-key permission.
///
/// The buttons are AppKit-backed (`AppKitPairingButton`) because the host
/// window contains a WebView whose first-responder steals mouse events from
/// SwiftUI controls.
struct PairingDialog: View {
    @ObservedObject var coordinator: PairApprovalCoordinator

    var body: some View {
        if let prompt = coordinator.currentPrompt {
            content(for: prompt)
        }
    }

    @ViewBuilder
    private func content(for prompt: TrustedComputers.Request) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Allow this computer to control Kelpie?")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name (self-reported):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(prompt.clientName.isEmpty ? "(no name)" : prompt.clientName)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("From:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(prompt.sourceAddress)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            Text("Computer key: \(prompt.publicKey)")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

            Text(
                "Allow this computer to control Kelpie, even when its IP changes. This stays allowed until you revoke it in Settings."
            )
            .font(.callout)
            .foregroundColor(.secondary)

            if let error = coordinator.approvalError {
                Text(error).font(.callout).foregroundColor(.red)
            }

            VStack(spacing: 8) {
                // No is the default — first in stacking order, prominent
                // style, and bound to Return.
                AppKitPairingButton(
                    title: "No",
                    style: .destructiveDefault,
                    accessibilityID: "pair.dialog.no",
                    action: { coordinator.deny(requestId: prompt.requestId) }
                )
                .frame(height: 32)

                AppKitPairingButton(
                    title: "Allow computer",
                    style: .warning,
                    accessibilityID: "pair.dialog.always",
                    action: { coordinator.approve(requestId: prompt.requestId) }
                )
                .frame(height: 32)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

/// View-modifier that attaches the pairing dialog to any view. Apply this
/// once at the root of the browser scene so prompts surface regardless of
/// which screen is active.
struct PairingDialogModifier: ViewModifier {
    @ObservedObject var coordinator: PairApprovalCoordinator

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(
                get: { coordinator.currentPrompt != nil },
                set: { newValue in
                    if !newValue, let id = coordinator.currentPrompt?.requestId {
                        // Dismiss by sheet close is equivalent to denial.
                        coordinator.deny(requestId: id)
                    }
                }
            )
        ) {
            PairingDialog(coordinator: coordinator)
        }
    }
}

extension View {
    func pairingDialog(coordinator: PairApprovalCoordinator) -> some View {
        modifier(PairingDialogModifier(coordinator: coordinator))
    }
}

/// AppKit-backed button used by the pairing dialog. Bypasses SwiftUI gesture
/// recognition so a focused WebView in the host window cannot swallow clicks.
struct AppKitPairingButton: NSViewRepresentable {
    enum Style {
        case normal
        case destructiveDefault  // Return key triggers this; prominent tint
        case warning             // Tinted orange to slow muscle-memory taps
    }

    let title: String
    let style: Style
    let accessibilityID: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: title,
            target: context.coordinator,
            action: #selector(Coordinator.handlePress)
        )
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.setAccessibilityIdentifier(accessibilityID)
        applyStyle(to: button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        applyStyle(to: button)
    }

    private func applyStyle(to button: NSButton) {
        switch style {
        case .normal:
            button.keyEquivalent = ""
            button.bezelColor = nil
            button.hasDestructiveAction = false
        case .destructiveDefault:
            button.keyEquivalent = "\r"
            button.bezelColor = nil
            button.hasDestructiveAction = true
        case .warning:
            button.keyEquivalent = ""
            button.bezelColor = NSColor.systemOrange
            button.hasDestructiveAction = false
        }
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func handlePress() { action() }
    }
}
