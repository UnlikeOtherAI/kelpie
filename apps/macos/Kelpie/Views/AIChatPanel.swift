import SwiftUI

enum AIPanelTab: String, CaseIterable {
    case chat = "Chat"
    case models = "Models"
}

@MainActor
final class AIChatSession: ObservableObject {
    @Published var messages: [AIChatMessage] = []
    @Published var input = ""
    @Published var isSending = false
    @Published var errorMessage: String?

    func reset() {
        messages = []
        input = ""
        isSending = false
        errorMessage = nil
    }

    func send(using aiState: AIState) async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let userMessage = AIChatMessage(role: .user, text: prompt)
        messages.append(userMessage)
        input = ""
        errorMessage = nil
        isSending = true

        do {
            let reply = try await aiState.ask(prompt: prompt, history: messages.dropLast().map { $0 })
            messages.append(AIChatMessage(role: .assistant, text: reply))
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
    }
}

struct AIChatPanel: View {
    @ObservedObject var aiState: AIState
    @ObservedObject var session: AIChatSession
    @Binding var selectedTab: AIPanelTab
    let onClose: () -> Void
    @State private var showHFTokenPopover = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let error = aiState.lastError {
                panelError(error, dismiss: aiState.dismissError)
            }

            if let error = session.errorMessage {
                panelError(error) {
                    session.errorMessage = nil
                }
            }

            Group {
                switch selectedTab {
                case .chat:
                    chatTab
                case .models:
                    modelsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(AIPanelTab.allCases, id: \.self) { tab in
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
                    .overlay(
                        AppKitInvisibleButton(
                            accessibilityID: "browser.ai.tab.\(tab.rawValue.lowercased())",
                            accessibilityLabel: tab.rawValue
                        ) { selectedTab = tab }
                    )
            }

            Spacer()

            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .overlay(
                    AppKitInvisibleButton(
                        accessibilityID: "browser.ai.panel.close",
                        accessibilityLabel: "Close AI panel"
                    ) { onClose() }
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var chatTab: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let model = aiState.activeModel {
                        HStack(spacing: 6) {
                            Image(systemName: "brain")
                                .foregroundStyle(Color.accentColor)
                            Text(model.name)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Load a model to start chatting.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(session.messages) { message in
                        AIChatBubble(message: message)
                    }

                    if session.isSending {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Type a question…", text: $session.input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(aiState.activeModel == nil || session.isSending)
                    .accessibilityIdentifier("browser.ai.chat.input")
                    .onSubmit {
                        Task {
                            await session.send(using: aiState)
                        }
                    }

                let canSend = aiState.activeModel != nil && !session.isSending && !session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                    .overlay(
                        AppKitInvisibleButton(
                            accessibilityID: "browser.ai.chat.send",
                            accessibilityLabel: "Send",
                            isEnabled: canSend
                        ) {
                            Task { await session.send(using: aiState) }
                        }
                    )

                Button {} label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(aiState.activeModel?.capabilities.contains("audio") == true ? Color.accentColor : .secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("Voice input is not wired in this panel yet.")
            }
            .padding(12)
        }
    }

    private var modelsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CollapsibleModelSection(
                    title: "NATIVE",
                    defaultsKey: "com.kelpie.macos.ai-section-native",
                    trailing: {
                        Spacer()
                        Button {
                            showHFTokenPopover = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 9))
                                Text("Set HF Token")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(aiState.huggingFaceToken.isEmpty ? .orange : .secondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("browser.ai.hf-token")
                        .popover(isPresented: $showHFTokenPopover, arrowEdge: .bottom) {
                            HFTokenPopover(token: $aiState.huggingFaceToken)
                        }
                    }
                ) {
                    ForEach(aiState.nativeModelCards) { card in
                        AINativeModelCardView(card: card, aiState: aiState)
                    }
                }

                CollapsibleModelSection(
                    title: "OLLAMA",
                    defaultsKey: "com.kelpie.macos.ai-section-ollama",
                    trailing: {
                        Circle()
                            .fill(aiState.ollamaReachable ? Color.green : Color.secondary.opacity(0.6))
                            .frame(width: 8, height: 8)
                        Text(aiState.ollamaReachable ? "online" : "offline")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                ) {
                    if aiState.ollamaModels.isEmpty {
                        Text(aiState.ollamaReachable ? "No Ollama models detected." : "Ollama is not reachable.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(aiState.ollamaModels) { model in
                            AIOllamaModelCardView(model: model, aiState: aiState)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func panelError(_ text: String, dismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

private struct CollapsibleModelSection<Content: View, Trailing: View>: View {
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

private struct AIChatBubble: View {
    let message: AIChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 24)
            } else {
                Spacer(minLength: 24)
                bubble
            }
        }
    }

    private var bubble: some View {
        Text(message.text)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(message.role == .assistant ? Color(nsColor: .controlBackgroundColor) : Color.accentColor.opacity(0.16))
            )
    }
}

private struct AINativeModelCardView: View {
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

private struct AIOllamaModelCardView: View {
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

private struct HFTokenPopover: View {
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
