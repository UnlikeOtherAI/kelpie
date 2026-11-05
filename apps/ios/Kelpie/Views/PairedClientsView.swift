import SwiftUI

/// Computer permissions, legacy client grants, temporary account sessions and recent denials.
struct PairedClientsView: View {
    @ObservedObject var coordinator: PairApprovalCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var refreshTick = 0

    var body: some View {
        List {
            trustedSection
            persistentSection
            sessionSection
            deniedSection
        }
        .id(refreshTick)
        .navigationTitle("Paired Clients")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var trustedSection: some View {
        Section("Trusted computers") {
            let computers = coordinator.store.trustedComputers.list()
            if computers.isEmpty {
                Text("No remote computers approved. Localhost is always allowed.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(computers) { computer in
                    pairingRow(name: computer.address, subtitle: computer.name) {
                        _ = coordinator.store.revokeComputer(address: computer.address)
                        refreshTick &+= 1
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var persistentSection: some View {
        Section("Earlier client approvals") {
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
        Section("Account and temporary access") {
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
            Button("Revoke", role: .destructive) {
                onRevoke()
            }
            .buttonStyle(.borderless)
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
