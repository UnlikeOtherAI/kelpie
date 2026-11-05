import SwiftUI

/// Modal sheet shown when an unauthenticated client requests pairing.
/// Hosted by `BrowserView` and bound to the shared `PairApprovalCoordinator`.
///
/// Deny is the default; allowing a computer grants persistent IP permission.
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

            Text(
                "Allow all clients at this IP to control Kelpie. This stays allowed until you revoke it in Settings."
            )
            .font(.callout)
            .foregroundColor(.secondary)

            if let error = coordinator.approvalError {
                Text(error).font(.callout).foregroundColor(.red)
            }

            VStack(spacing: 8) {
                // No is the default — first in stacking order, prominent
                // tinted style, and triggered by the Return key.
                Button(role: .cancel) {
                    coordinator.deny(requestId: prompt.requestId)
                } label: {
                    Text("No")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)

                Button {
                    coordinator.approve(requestId: prompt.requestId, persist: true)
                } label: {
                    Text("Allow computer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.orange)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
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
                        // Dismiss by sheet-swipe is equivalent to denial.
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
