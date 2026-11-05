import Foundation

/// Holds only the private, preflight-validated scalar plan for one edit.
struct IOSPacedTypingPlan {
    let clearFirst: Bool
    let delayMs: Int
    let scalars: [String]

    init(action: String, text: String, delay: Int) throws {
        guard let input = IOSBoundWorkflow.json(["action": action, "text": text, "typingDelayMs": delay]),
              let pointer = kelpie_browser_script_typing_plan(input) else { throw IOSWorkflowFailure("INVALID_PACED_TYPING") }
        defer { kelpie_mcp_free_string(pointer) }
        guard let result = IOSBoundWorkflow.decode(String(cString: pointer)), result["valid"] as? Bool == true,
              let clearFirst = result["clearFirst"] as? Bool, let delayMs = result["typingDelayMs"] as? Int,
              let scalars = result["scalars"] as? [String], clearFirst == (action == "fill"), delayMs == delay,
              (1...1000).contains(delayMs), scalars.count <= 1000,
              max(0, scalars.count - 1) * delayMs <= 60000,
              scalars.allSatisfy({ $0.unicodeScalars.count == 1 }),
              scalars.joined().utf8.elementsEqual(text.utf8) else { throw IOSWorkflowFailure("INVALID_PACED_TYPING") }
        self.clearFirst = clearFirst
        self.delayMs = delayMs
        self.scalars = scalars
    }
}
