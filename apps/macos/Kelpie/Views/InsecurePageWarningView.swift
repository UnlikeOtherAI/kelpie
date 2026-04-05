import SwiftUI

struct InsecurePageWarningView: View {
    let url: URL
    @Binding var skipInFuture: Bool
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            VStack(spacing: 6) {
                Text("Not Secure")
                    .font(.title2.bold())

                Text(url.host ?? url.absoluteString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("This page uses an unencrypted connection. Any data sent may be visible to others on your network.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            Toggle(isOn: $skipInFuture) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("I'm a developer — don't warn me again")
                        .font(.system(size: 13, weight: .medium))
                    Text("All HTTP and local network URLs will load without this prompt.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .tint(.orange)
            .toggleStyle(.switch)

            HStack(spacing: 12) {
                Button("Go Back") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Button("Continue Anyway") { onContinue() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(28)
        .frame(width: 380)
    }
}
