import Foundation
import Combine

/// A conversation belongs to one live tab, including while its panel is hidden.
@MainActor
final class AIChatSession: ObservableObject {
    let tabId: String
    @Published var messages: [AIChatMessage] = []
    @Published var input = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var allowActions = false
    private var isClosed = false

    init(tabId: String) {
        self.tabId = tabId
    }

    func close() {
        isClosed = true
        messages = []
        input = ""
        errorMessage = nil
        isSending = false
        allowActions = false
    }

    func stop(using aiState: AIState) {
        Task { await aiState.cancelInference() }
    }

    func send(using aiState: AIState) async {
        let actions = allowActions
        await send { prompt, history in
            try await aiState.ask(prompt: prompt, history: history, tabId: self.tabId, allowActions: actions)
        }
    }

    func send(request: (String, [AIChatMessage]) async throws -> AIChatReply) async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isClosed, !isSending, !prompt.isEmpty else { return }
        let history = messages
        messages.append(AIChatMessage(role: .user, text: prompt))
        input = ""
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            let reply = try await request(prompt, history)
            guard !isClosed else { return }
            messages.append(AIChatMessage(role: .assistant, text: reply.text, detail: reply.detail))
        } catch let failure as AIChatFailure {
            guard !isClosed else { return }
            messages.append(AIChatMessage(role: .assistant, text: "⚠︎ \(failure.message)", detail: failure.reply.detail))
        } catch {
            guard !isClosed else { return }
            errorMessage = error.localizedDescription
        }
    }
}
