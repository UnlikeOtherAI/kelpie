import SwiftUI

struct AIStatusView: View {
    @ObservedObject private var engine = InferenceEngine.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "brain")
                    .font(.title2)
                Text("Local AI")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Divider()

            if engine.isLoaded, let name = engine.modelName {
                statusRow(label: "Status", value: "Loaded", color: .green)
                statusRow(label: "Model", value: name, color: .primary)
                if !engine.capabilities.isEmpty {
                    statusRow(label: "Capabilities", value: engine.capabilities.joined(separator: ", "), color: .primary)
                }
                statusRow(label: "Memory", value: "\(engine.memoryUsageMB) MB", color: .secondary)
            } else {
                statusRow(label: "Status", value: "No model loaded", color: .secondary)
                Text("Load a model via the CLI or HTTP API to enable local inference.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 380, height: 260)
    }

    private func statusRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            Text(value)
                .foregroundStyle(color)
            Spacer()
        }
        .font(.body)
    }
}
