import Foundation

struct AIChatMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    /// Agent steps and reasoning, shown on demand under the answer. Never
    /// sent back to the model.
    var detail: String?

    var apiPayload: [String: String] {
        ["role": role.rawValue, "content": text]
    }
}

/// One `ai-infer` answer as the chat panel shows it.
struct AIChatReply: Equatable {
    let text: String
    let detail: String?

    init(text: String, detail: String? = nil) {
        self.text = text
        self.detail = detail
    }

    init(response: [String: Any]) {
        let answer = response["response"] as? String ?? ""
        text = (response["completed"] as? Bool) == false ? "⚠︎ Step budget used up. \(answer)" : answer
        var lines: [String] = []
        if let tasks = response["tasks"] as? [[String: Any]], !tasks.isEmpty {
            lines.append("Tasks:")
            for task in tasks {
                lines.append("\((task["done"] as? Bool ?? false) ? "✓" : "○") \(task["task"] as? String ?? "")")
            }
            lines.append("")
        }
        if let steps = response["steps"] as? [[String: Any]], !steps.isEmpty {
            for (index, step) in steps.enumerated() {
                let mark = (step["ok"] as? Bool ?? false) ? "✓" : "✗"
                let args = step["args"] as? String ?? ""
                let duration = step["ms"] as? Int ?? 0
                lines.append("\(index + 1). \(mark) \(step["tool"] as? String ?? "?") \(args) — \(duration) ms")
            }
        }
        if let time = response["inferenceTimeMs"] as? Int {
            let model = response["model"] as? String ?? ""
            lines.append(String(format: "%.1f s", Double(time) / 1_000) + (model.isEmpty ? "" : " · \(model)"))
        }
        if let reasoning = response["reasoning"] as? String, !reasoning.isEmpty {
            lines.append("")
            lines.append("Reasoning:")
            lines.append(String(reasoning.prefix(4_000)))
        }
        detail = lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// An agent run that failed after taking steps.
struct AIChatFailure: Error {
    let message: String
    let reply: AIChatReply
}
