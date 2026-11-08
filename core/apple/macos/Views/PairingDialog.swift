import SwiftUI
import AppKit

/// Modal sheet shown when an unauthenticated client requests pairing.
/// Hosted by `BrowserView` and bound to the shared `PairApprovalCoordinator`.
///
/// Per the design (Codex finding #24): the default button is `No`. `Always`
/// is visually distinct and never the default — return-key triggers cancel.
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
    private func content(for prompt: PairingStore.PendingRequest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Allow this client to control this browser?")
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

            Text(
                "This client will be able to navigate, type, screenshot, run JavaScript, and read cookies."
            )
            .font(.callout)
            .foregroundColor(.secondary)

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
                    title: "Yes, once",
                    style: .normal,
                    accessibilityID: "pair.dialog.yes-once",
                    action: { coordinator.approve(requestId: prompt.requestId, persist: false) }
                )
                .frame(height: 32)

                AppKitPairingButton(
                    title: "Always allow",
                    style: .warning,
                    accessibilityID: "pair.dialog.always",
                    action: { coordinator.approve(requestId: prompt.requestId, persist: true) }
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
