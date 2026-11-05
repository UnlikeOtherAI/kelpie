import AppKit

/// Latches sensitive or uncertain input before later guards can replace the primary error.
@MainActor
final class ScriptWorkflowPrivacy {
    private(set) var secrets: [String]
    private(set) var discardMedia = false
    private var knownSecrets: Set<String>
    private let captures: Bool

    init(secrets: [String], captures: Bool) {
        self.secrets = secrets
        knownSecrets = Set(secrets)
        self.captures = captures
    }

    func consume(_ result: [String: Any], text: String?) {
        guard let sensitive = result["sensitive"] as? Bool else { uncertain(text: text); return }
        guard sensitive else {
            if result["sensitivityKnown"] as? Bool != true { uncertain(text: text) }
            return
        }
        uncertain(text: text)
    }

    func uncertain(text: String?) {
        if let text, knownSecrets.insert(text).inserted { secrets.append(text) }
        if captures { discardMedia = true }
    }
}

@MainActor
final class ScriptWorkflowActions {
    typealias Body = [String: Any]
    let workflow: ScriptBoundWorkflow
    let tab: ScriptWorkflowTab
    let presentation: ScriptPresentation
    let router: Router
    let check: () async throws -> Void
    var capture: ScriptCapture?
    private(set) var outputs: Body = [:]
    private let privacy: ScriptWorkflowPrivacy
    var secrets: [String] { privacy.secrets }
    var discardMedia: Bool { privacy.discardMedia }

    init(
        workflow: ScriptBoundWorkflow,
        tab: ScriptWorkflowTab,
        presentation: ScriptPresentation,
        router: Router,
        check: @escaping () async throws -> Void
    ) {
        self.workflow = workflow
        self.tab = tab
        self.presentation = presentation
        self.router = router
        self.check = check
        privacy = ScriptWorkflowPrivacy(secrets: workflow.sensitiveValues, captures: workflow.capture != nil)
    }

    func execute(_ step: Body, index: Int) async throws {
        try await check()
        let action = step["action"] as? String ?? ""
        switch action {
        case "click", "tap", "type", "fill":
            try await interact(step, action: action, index: index)
            return
        case "navigate":
            presentation.clear()
            try await tab.navigate(step["url"] as? String ?? "")
        case "scroll":
            presentation.clear()
            try await tab.scroll(step)
        case "wait": try await wait(milliseconds: step["ms"] as? Int ?? 0)
        case "assert", "wait-ready": try await predicate(step, action: action)
        case "commentary": presentation.show(step)
        case "screenshot": break
        case "output": try store(try await tab.output(step["source"] as? String ?? ""), step: step)
        case "extract": try store(try await read("tab.extract", params: step["params"] as? Body ?? [:]), step: step)
        default: throw ScriptWorkflowFailure("UNSUPPORTED_SCRIPT_ACTION")
        }
        if workflow.stepScreenshots || action == "screenshot" {
            do { try await capture?.screenshot(index: index) } catch {
                if ["navigate", "scroll"].contains(action) { throw ScriptWorkflowFailure("CAPTURE_AFTER_ACTION_FAILED", mayHaveCompleted: true) }
                throw error
            }
        }
    }

    private func store(_ value: Any, step: Body) throws {
        guard let name = step["name"] as? String else { throw ScriptWorkflowFailure("INVALID_OUTPUT") }
        outputs[name] = value
        guard let json = ScriptBoundWorkflow.json(outputs), json.utf8.count <= 262144 else {
            outputs.removeValue(forKey: name)
            throw ScriptWorkflowFailure("OUTPUT_BUDGET_EXCEEDED")
        }
    }

    private func read(_ method: String, params: Body) async throws -> Body {
        try tab.requireCurrent()
        let document = tab.document
        let result = await router.browserControl(["version": 1, "method": method, "tabId": tab.id, "params": params])
        try await check()
        try tab.requireCurrent()
        guard document == tab.document else { throw ScriptWorkflowFailure("DOCUMENT_CHANGED") }
        guard result["ok"] as? Bool == true, let value = result["value"] as? Body else {
            throw ScriptWorkflowFailure("OBSERVATION_FAILED")
        }
        return value
    }

    private func predicate(_ step: Body, action: String) async throws {
        let end = ProcessInfo.processInfo.systemUptime + Double(step["timeoutMs"] as? Int ?? 10000) / 1000
        repeat {
            try await check()
            if action == "wait-ready" {
                var params: Body = ["state": step["state"] ?? "interactive"]
                params["selector"] = step["selector"]
                if try await read("tab.ready", params: params)["ready"] as? Bool == true { return }
            } else {
                let state = step["state"] as? String
                let result = try await tab.target(step["target"] as? Body ?? [:], observe: true)
                if result["ok"] as? Bool == true {
                    if state == "visible" || (state == "enabled" && result["enabled"] as? Bool == true) { return }
                } else if result["error"] as? String == "TARGET_NOT_FOUND" {
                    if state == "hidden" { return }
                } else { try requireOK(result) }
            }
            try await wait(milliseconds: 80)
        } while ProcessInfo.processInfo.systemUptime < end
        throw ScriptWorkflowFailure("TIMEOUT")
    }

    func wait(milliseconds: Int) async throws {
        let end = ProcessInfo.processInfo.systemUptime + Double(max(0, milliseconds)) / 1000
        repeat {
            try await check()
            let remaining = end - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 { return }
            try await Task.sleep(nanoseconds: UInt64(min(0.05, remaining) * 1_000_000_000))
        } while true
    }

    private func requireOK(_ result: Body) throws {
        guard result["sensitive"] is Bool else {
            throw ScriptWorkflowFailure("TARGET_FAILED", mayHaveCompleted: result["mayHaveCompleted"] as? Bool == true)
        }
        guard result["ok"] as? Bool == true else {
            // The isolated-world fixed target function supplies these diagnostic enums.
            let allowed: Set<String> = [
                "AMBIGUOUS_TARGET", "INPUT_UNCERTAIN", "INVALID_TARGET", "INVALID_TARGET_OPERATION",
                "SENSITIVE_CAPTURE_REFUSED", "STALE_TARGET", "TARGET_MOVED", "TARGET_NOT_EDITABLE", "TARGET_NOT_FOUND",
                "TARGET_NOT_INTERACTABLE", "TARGET_OBSCURED", "TARGET_OUTSIDE_VIEWPORT",
                "TARGET_QUERY_LIMIT", "VIEWPORT_CHANGED"
            ]
            let code = result["error"] as? String ?? ""
            throw ScriptWorkflowFailure(allowed.contains(code) ? code : "TARGET_FAILED",
                                        mayHaveCompleted: result["mayHaveCompleted"] as? Bool == true)
        }
    }

    private func interact(_ step: Body, action: String, index: Int) async throws {
        let target = step["target"] as? Body ?? [:]
        let editing = action == "type" || action == "fill"
        let text = editing ? step["text"] as? String : nil
        let consume = { [privacy] (result: Body) in privacy.consume(result, text: text) }
        let uncertain = { [privacy] in privacy.uncertain(text: text) }
        if step["sensitive"] as? Bool == true { consume(["sensitive": true]) }
        let document = tab.document
        let viewport = try await tab.viewport()
        let found = try await tab.target(target, refuseSensitive: workflow.capture != nil, consume: consume, uncertain: uncertain)
        try requireOK(found)
        guard let token = found["token"] as? String, let x = found["x"] as? Double, let y = found["y"] as? Double else {
            throw ScriptWorkflowFailure("INVALID_TARGET")
        }
        if discardMedia { throw ScriptWorkflowFailure("SENSITIVE_CAPTURE_REFUSED") }
        let paced = workflow.pacedPlans[index]
        if let paced, paced.operations.isEmpty {
            try requireOK(try await tab.target(
                target, token: token, refuseSensitive: workflow.capture != nil, consume: consume, uncertain: uncertain
            ))
            if workflow.stepScreenshots { try await capture?.screenshot(index: index) }
            return
        }
        if editing {
            #if DEBUG
            await tab.debugEditFocus("before", targetFocused: found["focused"] as? Bool)
            #endif
            do { try await tab.prepareEditFocus() } catch {
                #if DEBUG
                await tab.debugEditFocus("after", targetFocused: nil)
                #endif
                throw error
            }
        }
        let point = viewport.displayPoint(CGPoint(x: x, y: y))
        try await presentation.move(to: point, options: workflow.settings["pointer"] as? Body ?? [:], check: check)
        var settings = workflow.settings["tapIndicator"] as? Body ?? [:]
        settings["radius"] = Double(CGFloat(settings["radius"] as? Double ?? 20) * viewport.bounds.width / viewport.visible.width)
        let verified = try await tab.target(
            target, token: token, refuseSensitive: workflow.capture != nil, consume: consume, uncertain: uncertain
        )
        try requireOK(verified)
        #if DEBUG
        if editing, !discardMedia { await tab.debugEditFocus("after", targetFocused: verified["focused"] as? Bool) }
        #endif
        presentation.indicate(at: point, options: settings, hold: capture?.hasMovies == true)
        if workflow.stepScreenshots { try await capture?.screenshot(index: index) }
        try await capture?.ensureMarkerAdmission()
        presentation.releaseMarker()
        try await check()
        let current = try await tab.viewport()
        guard tab.document == document, viewport == current else { throw ScriptWorkflowFailure("STALE_TARGET") }
        if let paced {
            try await performPaced(
                paced,
                target: target,
                token: token,
                document: document,
                viewport: viewport,
                consume: consume,
                uncertain: uncertain
            )
            return
        }
        let edit: Body? = editing ? ["action": action, "text": step["text"] ?? ""] : nil
        let result = try await tab.target(
            target,
            token: token,
            dispatch: !editing,
            edit: edit,
            refuseSensitive: workflow.capture != nil,
            consume: consume,
            uncertain: uncertain
        )
        try requireOK(result)
        if discardMedia { throw ScriptWorkflowFailure("SENSITIVE_CAPTURE_REFUSED", mayHaveCompleted: true) }
        do { try await check() } catch {
            throw ScriptWorkflowFailure("INPUT_INTERRUPTED", mayHaveCompleted: true)
        }
    }

    /// An acknowledged scalar still needs privacy classification before continuing.
    static func requirePacedAckShape(_ result: Body) throws {
        let validStatus = result["ok"] as? Bool == true ? result["error"] == nil : result["error"] is String
        guard result["ok"] is Bool, validStatus, result["sensitive"] is Bool, result["sensitivityKnown"] is Bool,
              result["mayHaveCompleted"] is Bool else {
            throw ScriptWorkflowFailure("INPUT_UNCERTAIN", mayHaveCompleted: true)
        }
    }

    static func requirePacedClassification(_ result: Body, hasFurther: Bool, discardMedia: Bool) throws {
        if discardMedia { throw ScriptWorkflowFailure("SENSITIVE_CAPTURE_REFUSED", mayHaveCompleted: true) }
        if hasFurther && result["sensitivityKnown"] as? Bool != true {
            throw ScriptWorkflowFailure("INPUT_UNCERTAIN", mayHaveCompleted: true)
        }
    }

    private func performPaced(
        _ plan: ScriptPacedTyping,
        target: Body,
        token: String,
        document: String,
        viewport: ScriptWorkflowTab.Viewport,
        consume: @escaping @MainActor (Body) -> Void,
        uncertain: @escaping @MainActor () -> Void
    ) async throws {
        var completedInput = false
        do {
            let operations = plan.operations
            for (index, operation) in operations.enumerated() {
                if operation.delayBeforeMs > 0 { try await wait(milliseconds: operation.delayBeforeMs) }
                try await check()
                let current = try await tab.viewport()
                guard tab.document == document, viewport == current else { throw ScriptWorkflowFailure("STALE_TARGET") }
                var edit: Body = ["action": operation.action, "text": operation.text]
                if operation.requireFocused { edit["requireFocused"] = true }
                let result = try await tab.target(
                    target,
                    token: token,
                    edit: edit,
                    refuseSensitive: workflow.capture != nil,
                    allowFinalMutationDocumentChange: index + 1 == operations.count,
                    consume: consume,
                    uncertain: uncertain
                )
                do { try Self.requirePacedAckShape(result) } catch { uncertain(); throw error }
                if result["mayHaveCompleted"] as? Bool == true { completedInput = true }
                try requireOK(result)
                guard result["mayHaveCompleted"] as? Bool == true else { uncertain(); throw ScriptWorkflowFailure("INPUT_UNCERTAIN", mayHaveCompleted: true) }
                try Self.requirePacedClassification(result, hasFurther: index + 1 < operations.count, discardMedia: discardMedia)
            }
            try await check()
        } catch let failure as ScriptWorkflowFailure {
            if completedInput && !failure.mayHaveCompleted {
                throw ScriptWorkflowFailure(failure.code, mayHaveCompleted: true)
            }
            throw failure
        } catch {
            throw ScriptWorkflowFailure(Task.isCancelled ? "SCRIPT_ABORTED" : "WORKFLOW_FAILED",
                                        mayHaveCompleted: completedInput)
        }
    }

}
