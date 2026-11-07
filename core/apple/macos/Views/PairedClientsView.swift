import SwiftUI
import AppKit

/// Settings sub-screen listing paired clients with revoke actions.
///
/// Three sections mirror the design doc:
///   - Paired clients   — persistent ("Always allow") approvals.
///   - Active sessions  — in-memory ("Yes, once") approvals.
///   - Recently denied  — informational; cleared after 10 min.
struct PairedClientsView: View {
    @ObservedObject var coordinator: PairApprovalCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var refreshTick = 0

    var body: some View {
        VStack(spacing: 0) {
            Form {
                persistentSection
                sessionSection
                deniedSection
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                AppKitPairingButton(
                    title: "Done",
                    style: .destructiveDefault,
                    accessibilityID: "paired-clients.done",
                    action: dismiss.callAsFunction
                )
                .frame(width: 92, height: 34)
            }
            .padding()
        }
        .frame(width: 460, height: 520)
    }

    @ViewBuilder
    private var persistentSection: some View {
        Section("Persistent (Always allow)") {
            let records = coordinator.store.listPersistent()
            if records.isEmpty {
                Text("No persistent pairings.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(records, id: \.clientId) { record in
                    pairingRow(name: record.clientName, subtitle: timeAgo(ms: record.approvedAt)) {
                        revoke(clientId: record.clientId)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sessionSection: some View {
        Section("Active sessions (Yes, once)") {
            let sessions = coordinator.store.listSessions()
            if sessions.isEmpty {
                Text("No active session pairings.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(sessions, id: \.clientId) { record in
                    pairingRow(name: record.clientName, subtitle: timeAgo(ms: record.approvedAt)) {
                        revoke(clientId: record.clientId)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var deniedSection: some View {
        Section("Recently denied") {
            let denied = coordinator.store.listDeniedSources()
            if denied.isEmpty {
                Text("No suppressed sources.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(denied, id: \.address) { entry in
                    HStack {
                        Text(entry.address)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text(expiresIn(ms: entry.expiresAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func pairingRow(name: String, subtitle: String, onRevoke: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            AppKitPairingButton(
                title: "Revoke",
                style: .warning,
                accessibilityID: "paired-clients.revoke",
                action: onRevoke
            )
            .frame(width: 88, height: 26)
        }
    }

    private func revoke(clientId: String) {
        _ = coordinator.store.revoke(clientId: clientId)
        refreshTick &+= 1
    }

    private func timeAgo(ms: Double) -> String {
        let seconds = max(0, (Date().timeIntervalSince1970 * 1_000 - ms) / 1_000)
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) hr ago" }
        return "\(Int(seconds / 86_400)) days ago"
    }

    private func expiresIn(ms: Double) -> String {
        let seconds = max(0, (ms - Date().timeIntervalSince1970 * 1_000) / 1_000)
        if seconds < 60 { return "\(Int(seconds)) s left" }
        return "\(Int(seconds / 60)) min left"
    }
}
