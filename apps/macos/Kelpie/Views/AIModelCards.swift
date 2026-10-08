import SwiftUI

// Model-list building blocks for the AI panel's Models tab.

struct CollapsibleModelSection<Content: View, Trailing: View>: View {
    let title: String
    let defaultsKey: String
    let trailing: () -> Trailing
    let content: () -> Content

    @State private var isExpanded: Bool

    init(
        title: String,
        defaultsKey: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.defaultsKey = defaultsKey
        self.trailing = trailing
        self.content = content
        let saved = UserDefaults.standard.object(forKey: defaultsKey) as? Bool
        _isExpanded = State(initialValue: saved ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
                UserDefaults.standard.set(isExpanded, forKey: defaultsKey)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    trailing()
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
            }
        }
    }
}

struct AINativeModelCardView: View {
    let card: AINativeModelCard
    @ObservedObject var aiState: AIState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: card.model.capabilities.contains("vision") ? "eye" : "circle.slash")
                    .foregroundStyle(card.isActive ? Color.accentColor : .secondary)
                Text(card.model.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if card.isActive {
                    Text("Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }

            Text(card.model.description.summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("\(formattedSize(card.model.sizeBytes)) • ~\(format(card.model.ramWhenLoadedGB)) GB RAM")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            fitnessText

            HStack(spacing: 8) {
                Button(card.buttonTitle) {
                    handlePrimaryAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(primaryDisabled)
                .accessibilityIdentifier("browser.ai.native.\(card.id).action")

                if card.isDownloaded && !card.isActive {
                    Button("Remove") {
                        aiState.removeNativeModel(id: card.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("browser.ai.native.\(card.id).remove")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private var fitnessText: some View {
        switch card.fitness {
        case .recommended:
            EmptyView()
        case .possible(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        case .notRecommended(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        case .noStorage(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
        }
    }

    private var primaryDisabled: Bool {
        if card.downloadState == .downloading {
            return true
        }
        if !card.isDownloaded, case .noStorage = card.fitness {
            return true
        }
        return false
    }

    private func handlePrimaryAction() {
        if card.isActive {
            Task { _ = await aiState.unloadModel() }
        } else if card.isDownloaded {
            Task { _ = await aiState.loadNativeModel(id: card.id) }
        } else {
            aiState.downloadNativeModel(id: card.id)
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        format(Double(bytes) / 1_000_000_000) + " GB"
    }

    private func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

struct AIOllamaModelCardView: View {
    let model: AIOllamaModel
    @ObservedObject var aiState: AIState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: model.capabilities.contains("vision") ? "eye" : "circle.slash")
                    .foregroundStyle(model.isActive ? Color.accentColor : .secondary)
                Text(model.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("[server]")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if model.isActive {
                    Text("Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }

            Text("Managed by Ollama — Kelpie can use it but does not store it locally.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(model.isActive ? "Unload" : "Load") {
                    Task {
                        if model.isActive {
                            _ = await aiState.unloadModel()
                        } else {
                            _ = await aiState.loadOllamaModel(name: model.name)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("browser.ai.ollama.\(model.name).action")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct HFTokenPopover: View {
    @Binding var token: String
    @State private var draft: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hugging Face Token")
                .font(.system(size: 12, weight: .semibold))

            Text("Some models require authentication. Generate a token at huggingface.co/settings/tokens and paste it here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("hf_...", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .accessibilityIdentifier("browser.ai.hf-token.input")

            HStack {
                if !token.isEmpty {
                    Button("Clear") {
                        token = ""
                        draft = ""
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
                Button("Save") {
                    token = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("browser.ai.hf-token.save")
            }
        }
        .padding(14)
        .frame(width: 240)
        .onAppear {
            draft = token
        }
    }
}
