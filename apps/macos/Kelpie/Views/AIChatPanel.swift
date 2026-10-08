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
    /// Lets the OpenAI-compatible agent click and type in the current tab.
    /// Off by default; only the person can turn it on.
    @Published var allowActions = false

    func reset() {
        messages = []
        input = ""
        isSending = false
        errorMessage = nil
        allowActions = false
    }

    func stop(using aiState: AIState) {
        Task { await aiState.cancelInference() }
    }

    func send(using aiState: AIState, tabId: String?) async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let userMessage = AIChatMessage(role: .user, text: prompt)
        messages.append(userMessage)
        input = ""
        errorMessage = nil
        isSending = true

        do {
            let reply = try await aiState.ask(
                prompt: prompt,
                history: messages.dropLast().map { $0 },
                tabId: tabId,
                allowActions: allowActions
            )
            messages.append(AIChatMessage(role: .assistant, text: reply.text, detail: reply.detail))
        } catch let failure as AIChatFailure {
            messages.append(AIChatMessage(role: .assistant, text: "⚠︎ \(failure.message)", detail: failure.reply.detail))
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
    /// The tab the agent operates on (pinned per request).
    let activeTabId: String?
    @ObservedObject var endpointState = AIEndpointState.shared
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
                        if model.backend == .openai {
                            openAIChatControls
                        }
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
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            if aiState.activeModel?.backend == .openai {
                                AIPanelActionButton(title: "Stop", accessibilityID: "browser.ai.chat.stop") {
                                    session.stop(using: aiState)
                                }
                            }
                        }
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
                            await session.send(using: aiState, tabId: activeTabId)
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
                            Task { await session.send(using: aiState, tabId: activeTabId) }
                        }
                    )

                Image(systemName: "mic.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(aiState.activeModel?.capabilities.contains("audio") == true ? Color.accentColor : .secondary)
                    .frame(width: 28, height: 28)
                    .overlay(
                        AppKitInvisibleButton(
                            accessibilityID: "browser.ai.chat.mic",
                            accessibilityLabel: "Voice input",
                            isEnabled: false
                        ) {}
                    )
                    .help("Voice input is not wired in this panel yet.")
            }
            .padding(12)
        }
    }

    private var modelsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CollapsibleModelSection(
                    title: "HUGGING FACE",
                    defaultsKey: "com.kelpie.macos.ai-section-native",
                    trailing: {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 9))
                            Text("Set HF Token")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(aiState.huggingFaceToken.isEmpty ? .orange : .secondary)
                        .overlay(
                            AppKitInvisibleButton(
                                accessibilityID: "browser.ai.hf-token",
                                accessibilityLabel: "Set HF Token"
                            ) {
                                showHFTokenPopover = true
                            }
                        )
                        .popover(isPresented: $showHFTokenPopover, arrowEdge: .bottom) {
                            HFTokenPopover(token: $aiState.huggingFaceToken)
                        }
                    },
                    content: {
                        ForEach(aiState.nativeModelCards) { card in
                            AINativeModelCardView(card: card, aiState: aiState)
                        }
                    }
                )

                CollapsibleModelSection(
                    title: "OPENAI-COMPATIBLE",
                    defaultsKey: "com.kelpie.macos.ai-section-openai",
                    content: {
                        AIEndpointsSection(state: endpointState)
                    }
                )

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
                    },
                    content: {
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
                )
            }
            .padding(12)
        }
    }

    /// Endpoint health and the per-conversation action permission.
    private var openAIChatControls: some View {
        let card = endpointState.cards.first { $0.isActive }
        return VStack(alignment: .leading, spacing: 6) {
            if let card {
                Text("\(card.name): \(card.healthState.replacingOccurrences(of: "_", with: " "))")
                    .font(.system(size: 11))
                    .foregroundStyle(card.online ? Color.secondary : Color.orange)
                    .accessibilityIdentifier("browser.ai.chat.endpoint-health")
            }
            HStack(spacing: 6) {
                AIPanelActionButton(
                    title: session.allowActions ? "Page actions: allowed" : "Page actions: off",
                    accessibilityID: "browser.ai.chat.allow-actions",
                    prominent: session.allowActions
                ) {
                    session.allowActions.toggle()
                }
                Text(session.allowActions ? "The model may click and type in this tab." : "The model can only read this tab.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
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

private struct AIChatBubble: View {
    let message: AIChatMessage
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if message.role == .assistant {
                    bubble
                    Spacer(minLength: 24)
                } else {
                    Spacer(minLength: 24)
                    bubble
                }
            }
            if let detail = message.detail {
                AIPanelActionButton(
                    title: showDetail ? "Hide steps" : "Show steps",
                    accessibilityID: "browser.ai.chat.detail.\(message.id.uuidString)"
                ) {
                    showDetail.toggle()
                }
                if showDetail {
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var bubble: some View {
        Text(message.text)
            .textSelection(.enabled)
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
