import SwiftUI

/// The same control surface is reachable in Settings and beside a remotely driven page.
struct ConnectControls: View {
    @ObservedObject private var connection = NessieConnection.shared
    @ObservedObject private var account = UOAAccount.shared
    var compact = false

    var body: some View {
        if !compact || connection.running || connection.paused {
            HStack {
                Text(connection.running ? "Nessie is using this tab" : connection.status)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                if account.profile == nil {
                    EmptyView()
                } else if connection.requiresSignIn {
                    control("Sign in again", icon: "person.badge.key", id: "nessie.sign-in", action: connection.renewConsent)
                } else {
                    control(connection.paused ? "Resume Nessie" : "Pause Nessie",
                            icon: connection.paused ? "play.fill" : "pause.fill", id: "nessie.pause", action: connection.togglePause)
                    if connection.running { control("Stop Nessie", icon: "stop.fill", id: "nessie.stop", action: connection.stop) }
                }
            }
            .padding(8)
            .accessibilityIdentifier("nessie.controls")
        }
    }

    @ViewBuilder
    private func control(_ label: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        #if os(macOS)
        AppKitToolbarButton(systemName: icon, accessibilityID: id, accessibilityLabel: label, action: action)
        #else
        Button(label, action: action).accessibilityIdentifier(id)
        #endif
    }
}
