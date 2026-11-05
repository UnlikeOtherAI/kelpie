import Foundation

/// The generated contract normalizes the author's v1 workflow before the native run acquires a tab.
struct IOSBoundWorkflow {
    typealias Body = [String: Any]
    static let actions: Set<String> = [
        "navigate", "tap", "click", "fill", "type", "scroll", "wait", "wait-ready",
        "assert", "screenshot", "commentary", "output", "extract"
    ]
    static let capabilities: Body = [
        "success": true, "supportedVersions": [1], "inputGuarantee": "synthetic-coordinate"
    ]
    static func deviceCapabilities(videoAvailable: Bool) -> Body {
        [
            "supportedVersions": [1],
            "inputGuarantee": "synthetic-coordinate",
            "supportedActions": actions.sorted(),
            "captureFormats": ["gif", "screenshots"] + (videoAvailable ? ["video"] : []),
            "nativeSessions": false,
            "webMcp": ["available": false, "reason": "No registered real API and explicit host grant"],
            "lightpanda": ["available": false, "reason": "Desktop orchestration backend"]
        ]
    }

    let settings: Body
    let steps: [Body]
    let tabID: String
    let capture: Body?
    let stepScreenshots: Bool
    let sensitiveValues: [String]
    let pacedPlans: [Int: IOSPacedTypingPlan]

    init(_ body: Body) throws {
        guard let input = Self.json(body),
              let pointer = kelpie_browser_validate_script(input) else { throw IOSWorkflowFailure("INVALID_SCRIPT") }
        defer { kelpie_mcp_free_string(pointer) }
        guard let normalized = Self.decode(String(cString: pointer)), normalized["valid"] as? Bool == true,
              let script = normalized["script"] as? Body, let steps = script["actions"] as? [Body],
              let tabID = script["tabId"] as? String else { throw IOSWorkflowFailure("INVALID_SCRIPT") }
        guard script["sessionId"] == nil else { throw IOSWorkflowFailure("SESSION_UNSUPPORTED") }
        if let declarations = script["inputs"] as? Body, !declarations.isEmpty { throw IOSWorkflowFailure("UNRESOLVED_INPUT") }
        var secrets: [String] = []
        var names: Set<String> = []
        var hasScreenshot = false
        var pacedPlans: [Int: IOSPacedTypingPlan] = [:]
        for (index, step) in steps.enumerated() {
            guard let action = step["action"] as? String, Self.actions.contains(action) else {
                throw IOSWorkflowFailure("UNSUPPORTED_SCRIPT_ACTION")
            }
            if action == "fill" || action == "type" {
                let value = try Self.editText(step)
                pacedPlans[index] = try Self.pacedPlan(step, action: action, text: value)
                if step["sensitive"] as? Bool == true { secrets.append(value) }
            }
            if action == "output" || action == "extract" {
                guard let name = step["name"] as? String, names.insert(name).inserted else {
                    throw IOSWorkflowFailure("DUPLICATE_OUTPUT")
                }
            }
            hasScreenshot = hasScreenshot || action == "screenshot"
        }
        let requested = script["capture"] as? Body
        if !secrets.isEmpty && (hasScreenshot || requested != nil) {
            throw IOSWorkflowFailure("SENSITIVE_CAPTURE_REFUSED")
        }
        self.settings = script
        self.steps = steps
        self.tabID = tabID
        self.sensitiveValues = secrets
        self.pacedPlans = pacedPlans
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

    private static func pacedPlan(_ step: Body, action: String, text: String) throws -> IOSPacedTypingPlan? {
        guard let raw = step["typingDelayMs"] else { return nil }
        guard let delay = raw as? Int else { throw IOSWorkflowFailure("INVALID_PACED_TYPING") }
        return try IOSPacedTypingPlan(action: action, text: text, delay: delay)
    }

    private static func editText(_ step: Body) throws -> String {
        guard let value = step["text"] as? String else { throw IOSWorkflowFailure("UNRESOLVED_INPUT") }
        return value
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
