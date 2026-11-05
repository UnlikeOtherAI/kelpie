import Foundation

/// The generated contract normalizes the author's v1 workflow before the native run acquires a tab.
struct ScriptBoundWorkflow {
    typealias Body = [String: Any]
    static let actions: Set<String> = [
        "navigate", "tap", "click", "fill", "type", "scroll", "wait", "wait-ready",
        "assert", "screenshot", "commentary", "output", "extract"
    ]
    static let capabilities: Body = [
        "success": true, "supportedVersions": [1], "inputGuarantee": "synthetic-coordinate"
    ]
    let settings: Body
    let steps: [Body]
    let tabID: String
    let capture: Body?
    let stepScreenshots: Bool
    let sensitiveValues: [String]

    init(_ body: Body) throws {
        guard let input = Self.json(body),
              let pointer = kelpie_browser_validate_script(input) else { throw ScriptWorkflowFailure("INVALID_SCRIPT") }
        defer { kelpie_mcp_free_string(pointer) }
        guard let normalized = Self.decode(String(cString: pointer)), normalized["valid"] as? Bool == true,
              let script = normalized["script"] as? Body, let steps = script["actions"] as? [Body],
              let tabID = script["tabId"] as? String else { throw ScriptWorkflowFailure("INVALID_SCRIPT") }
        guard script["sessionId"] == nil else { throw ScriptWorkflowFailure("SESSION_UNSUPPORTED") }
        if let declarations = script["inputs"] as? Body, !declarations.isEmpty { throw ScriptWorkflowFailure("UNRESOLVED_INPUT") }
        var secrets: [String] = []
        var names: Set<String> = []
        var hasScreenshot = false
        for step in steps {
            guard let action = step["action"] as? String, Self.actions.contains(action) else {
                throw ScriptWorkflowFailure("UNSUPPORTED_SCRIPT_ACTION")
            }
            if action == "fill" || action == "type" {
                guard let value = step["text"] as? String else { throw ScriptWorkflowFailure("UNRESOLVED_INPUT") }
                if step["sensitive"] as? Bool == true { secrets.append(value) }
            }
            if action == "output" || action == "extract" {
                guard let name = step["name"] as? String, names.insert(name).inserted else {
                    throw ScriptWorkflowFailure("DUPLICATE_OUTPUT")
                }
            }
            hasScreenshot = hasScreenshot || action == "screenshot"
        }
        let requested = script["capture"] as? Body
        if !secrets.isEmpty && (hasScreenshot || requested != nil) {
            throw ScriptWorkflowFailure("SENSITIVE_CAPTURE_REFUSED")
        }
        self.settings = script
        self.steps = steps
        self.tabID = tabID
        self.sensitiveValues = secrets
        self.stepScreenshots = (requested?["formats"] as? [String])?.contains("screenshots") == true
        if var options = requested {
            if hasScreenshot, var formats = options["formats"] as? [String], !formats.contains("screenshots") {
                formats.append("screenshots")
                options["formats"] = formats
            }
            capture = options
        } else if hasScreenshot {
            capture = ["formats": ["screenshots"], "fps": 15, "maxWidth": 1280,
                       "maxDurationMs": 60000, "maxBytes": 67108864]
        } else {
            capture = nil
        }
    }

    static func json(_ body: Body) -> String? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ text: String) -> Body? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? Body
    }
}
