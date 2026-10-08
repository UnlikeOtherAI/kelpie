import Foundation

/// The agent's own structured plan. The model writes it with the
/// `update_task_list` tool; Kelpie uses it to tell whether the model still has
/// work left when it tries to stop, and shows it to the person.
///
/// Updating the list is bookkeeping, not a browser step, so it does not use
/// the step budget.
struct OpenAIAgentTaskList: Sendable {
    struct Item: Equatable, Sendable {
        let task: String
        let done: Bool

        var json: [String: Any] { ["task": task, "done": done] }
    }

    static let toolName = "update_task_list"
    static let maxItems = 20

    private(set) var items: [Item] = []

    var unfinished: [Item] { items.filter { !$0.done } }

    static var definition: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": toolName,
                "description": "Record your plan as a list of tasks and mark tasks done once you have verified them. " +
                    "Send the whole list every time. This does not use a browser step.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "tasks": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "task": ["type": "string", "description": "What needs doing"],
                                    "done": ["type": "boolean", "description": "True once done and verified"]
                                ],
                                "required": ["task", "done"]
                            ]
                        ]
                    ],
                    "required": ["tasks"]
                ] as [String: Any]
            ] as [String: Any]
        ]
    }

    /// Replaces the list from a tool call and returns the tool result text.
    mutating func apply(_ call: OpenAIToolCall) -> String {
        guard let raw = call.parsedArguments?["tasks"] as? [Any] else {
            return OpenAIAgentLoop.json(["ok": false, "error": "Send {\"tasks\": [{\"task\": \"…\", \"done\": false}]}."])
        }
        let parsed = raw.prefix(Self.maxItems).compactMap { entry -> Item? in
            guard let object = entry as? [String: Any],
                  let task = (object["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !task.isEmpty else { return nil }
            return Item(task: String(task.prefix(200)), done: object["done"] as? Bool ?? false)
        }
        items = parsed
        return OpenAIAgentLoop.json([
            "ok": true,
            "remaining": unfinished.map(\.task)
        ])
    }

    /// Kelpie's one-time reminder when the model answers with open tasks —
    /// the "needs another turn" signal, derived from the model's own plan.
    func unfinishedReminder() -> String? {
        let open = unfinished
        guard !open.isEmpty else { return nil }
        let list = open.enumerated().map { "\($0.offset + 1). \($0.element.task)" }.joined(separator: "\n")
        return """
        Kelpie: your task list still has unfinished tasks:
        \(list)
        If they still need doing, continue with the tools. If they are already done, mark them done and repeat your \
        complete final answer, because only your last message is shown to the person. If they cannot be done, \
        give your complete final answer and explain why.
        """
    }
}
