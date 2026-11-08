import Foundation

struct OpenAIToolCall: Equatable, Sendable {
    let id: String
    let name: String
    /// Raw JSON argument text exactly as the model produced it.
    let arguments: String

    /// Parsed arguments, or `nil` when the model produced invalid JSON.
    var parsedArguments: [String: Any]? {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [:] }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

struct OpenAIUsage: Equatable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
}

struct OpenAIChatResult: Equatable, Sendable {
    let content: String
    /// Reasoning text, kept apart from the answer and never sent back.
    let reasoning: String
    let toolCalls: [OpenAIToolCall]
    let finishReason: String?
    let usage: OpenAIUsage?
}

/// Folds streamed `chat.completion.chunk` deltas (or a single non-streamed
/// completion) into one result. Only choice 0 is used.
struct OpenAIChatAccumulator {
    private struct PartialToolCall {
        var id = ""
        var name = ""
        var arguments = ""
    }

    private var content = ""
    private var reasoning = ""
    private var toolCalls: [Int: PartialToolCall] = [:]
    private var finishReason: String?
    private var usage: OpenAIUsage?
    private(set) var sawDone = false
    private(set) var sawAnyChunk = false

    /// Applies one SSE `data:` payload. Returns `true` on `[DONE]`.
    @discardableResult
    mutating func apply(eventData: String) throws -> Bool {
        let trimmed = eventData.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "[DONE]" {
            sawDone = true
            return true
        }
        guard let data = trimmed.data(using: .utf8),
              let chunk = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw OpenAIEndpointError.malformedResponse("stream event was not a JSON object")
        }
        try apply(chunk: chunk)
        return false
    }

    mutating func apply(chunk: [String: Any]) throws {
        if let error = chunk["error"] {
            let message = (error as? [String: Any])?["message"] as? String ?? String(describing: error)
            throw OpenAIEndpointError.server(status: nil, message: OpenAIEndpointError.redact(message, apiKey: nil))
        }
        sawAnyChunk = true
        if let usage = chunk["usage"] as? [String: Any] {
            self.usage = Self.parseUsage(usage)
        }
        guard let choices = chunk["choices"] as? [[String: Any]],
              let choice = choices.first(where: { ($0["index"] as? Int ?? 0) == 0 }) else { return }
        if let reason = choice["finish_reason"] as? String { finishReason = reason }
        let delta = (choice["delta"] as? [String: Any]) ?? (choice["message"] as? [String: Any]) ?? [:]
        applyDelta(delta)
    }

    private mutating func applyDelta(_ delta: [String: Any]) {
        if let text = delta["content"] as? String { content += text }
        if let text = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String) {
            reasoning += text
        }
        guard let calls = delta["tool_calls"] as? [[String: Any]] else { return }
        for (position, call) in calls.enumerated() {
            let index = call["index"] as? Int ?? indexForUnindexedCall(call, position: position)
            var partial = toolCalls[index] ?? PartialToolCall()
            if let id = call["id"] as? String, !id.isEmpty, partial.id.isEmpty { partial.id = id }
            if let function = call["function"] as? [String: Any] {
                if let name = function["name"] as? String { partial.name += name }
                if let arguments = function["arguments"] as? String {
                    partial.arguments += arguments
                } else if let object = function["arguments"] as? [String: Any],
                          let data = try? JSONSerialization.data(withJSONObject: object),
                          let text = String(data: data, encoding: .utf8) {
                    // Some servers send already-parsed arguments in non-streamed replies.
                    partial.arguments += text
                }
            }
            toolCalls[index] = partial
        }
    }

    /// Servers that omit `index` either repeat one call's fragments or send
    /// whole calls; a new `id` starts a new call.
    private func indexForUnindexedCall(_ call: [String: Any], position: Int) -> Int {
        if let id = call["id"] as? String, !id.isEmpty {
            if let existing = toolCalls.first(where: { $0.value.id == id }) { return existing.key }
            return toolCalls.isEmpty ? position : (toolCalls.keys.max() ?? 0) + 1
        }
        return toolCalls.keys.max() ?? position
    }

    var isComplete: Bool { sawDone || finishReason != nil }

    func result() -> OpenAIChatResult {
        let calls = toolCalls.keys.sorted().compactMap { key -> OpenAIToolCall? in
            guard let partial = toolCalls[key], !partial.name.isEmpty else { return nil }
            let id = partial.id.isEmpty ? "call_\(key)" : partial.id
            return OpenAIToolCall(id: id, name: partial.name, arguments: partial.arguments)
        }
        return OpenAIChatResult(
            content: content,
            reasoning: reasoning,
            toolCalls: calls,
            finishReason: finishReason,
            usage: usage
        )
    }

    /// Parses a non-streamed `chat.completion` body.
    static func parseCompletion(_ data: Data) throws -> OpenAIChatResult {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw OpenAIEndpointError.malformedResponse("completion was not a JSON object")
        }
        guard object["error"] != nil || object["choices"] is [[String: Any]] else {
            throw OpenAIEndpointError.malformedResponse("completion has no choices")
        }
        var accumulator = Self()
        try accumulator.apply(chunk: object)
        return accumulator.result()
    }

    private static func parseUsage(_ raw: [String: Any]) -> OpenAIUsage {
        OpenAIUsage(
            promptTokens: raw["prompt_tokens"] as? Int,
            completionTokens: raw["completion_tokens"] as? Int,
            totalTokens: raw["total_tokens"] as? Int
        )
    }
}
