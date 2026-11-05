import Foundation

/// A private, fully preflighted scalar plan; literals never enter diagnostics or status.
struct ScriptPacedTyping {
    struct Operation {
        let action: String
        let text: String
        let requireFocused: Bool
        let delayBeforeMs: Int
    }

    let clearFirst: Bool
    let delayMs: Int
    let scalars: [String]

    init(action: String, text: String, delay: Any) throws {
        let request: [String: Any] = ["action": action, "text": text, "typingDelayMs": delay]
        guard let json = ScriptBoundWorkflow.json(request),
              let pointer = json.withCString({ kelpie_browser_script_typing_plan($0) }) else {
            throw ScriptWorkflowFailure("INVALID_PACED_TYPING")
        }
        defer { kelpie_mcp_free_string(pointer) }
        guard let plan = ScriptBoundWorkflow.decode(String(cString: pointer)), plan["valid"] as? Bool == true,
              let clear = plan["clearFirst"] as? Bool, clear == (action == "fill"),
              let delayMs = plan["typingDelayMs"] as? Int, (1...1000).contains(delayMs),
              let scalars = plan["scalars"] as? [String], scalars.count <= 1000,
              scalars.allSatisfy({ $0.unicodeScalars.count == 1 }),
              Array(scalars.joined().utf8) == Array(text.utf8),
              max(scalars.count - 1, 0) * delayMs <= 60000 else {
            throw ScriptWorkflowFailure("INVALID_PACED_TYPING")
        }
        clearFirst = clear
        self.delayMs = delayMs
        self.scalars = scalars
    }

    var operations: [Operation] {
        var result: [Operation] = []
        if clearFirst { result.append(Operation(action: "fill", text: "", requireFocused: false, delayBeforeMs: 0)) }
        for (index, scalar) in scalars.enumerated() {
            result.append(Operation(
                action: "type",
                text: scalar,
                requireFocused: clearFirst || index > 0,
                delayBeforeMs: index > 0 ? delayMs : 0
            ))
        }
        return result
    }
}
