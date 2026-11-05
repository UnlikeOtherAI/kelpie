import UIKit

@MainActor
final class IOSWorkflowActions {
    typealias Body = [String: Any]
    let workflow: IOSBoundWorkflow
    let tab: IOSWorkflowTab
    let presentation: IOSWorkflowPresentation
    let router: Router
    let check: () async throws -> Void
    var sampler: IOSFrameSampler?
    private(set) var outputs: Body = [:]
    private(set) var secrets: [String]
    private(set) var discardMedia = false

    init(
        workflow: IOSBoundWorkflow,
        tab: IOSWorkflowTab,
        presentation: IOSWorkflowPresentation,
        router: Router,
        check: @escaping () async throws -> Void
    ) {
        self.workflow = workflow
        self.tab = tab
        self.presentation = presentation
        self.router = router
        self.check = check
        secrets = workflow.sensitiveValues
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
            try await tab.navigate(step["url"] as? String ?? "", check: check)
        case "scroll":
            presentation.clear()
            try await tab.scroll(step)
        case "wait": try await wait(milliseconds: step["ms"] as? Int ?? 0)
        case "assert", "wait-ready": try await predicate(step, action: action)
        case "commentary": presentation.show(step)
        case "screenshot": break
        case "output": try store(try await tab.output(step["source"] as? String ?? ""), step: step)
        case "extract": try store(try await read("tab.extract", params: step["params"] as? Body ?? [:]), step: step)
        default: throw IOSWorkflowFailure("UNSUPPORTED_SCRIPT_ACTION")
        }
        if workflow.stepScreenshots || action == "screenshot" {
            do { try await sampler?.step(index) } catch {
                if ["navigate", "scroll"].contains(action) { throw IOSWorkflowFailure("CAPTURE_AFTER_ACTION_FAILED", mayHaveCompleted: true) }
                throw error
            }
        }
    }

    private func store(_ value: Any, step: Body) throws {
        guard let name = step["name"] as? String else { throw IOSWorkflowFailure("INVALID_OUTPUT") }
        outputs[name] = value
        guard let json = IOSBoundWorkflow.json(outputs), json.utf8.count <= 262144 else {
            outputs.removeValue(forKey: name)
            throw IOSWorkflowFailure("OUTPUT_BUDGET_EXCEEDED")
        }
    }

    private func read(_ method: String, params: Body) async throws -> Body {
        try tab.requireCurrent()
        let document = tab.document
        let result = await router.workflowRead(method: method, tabID: tab.id, params: params)
        try await check()
        try tab.requireCurrent()
        guard document == tab.document else { throw IOSWorkflowFailure("DOCUMENT_CHANGED") }
        guard result["ok"] as? Bool == true, let value = result["value"] as? Body else {
            #if DEBUG
            let code = (result["error"] as? Body)?["code"] as? String ?? "INVALID_VALUE"
            let known = ["BUSY", "TAB_CHANGED", "WEBVIEW_ERROR", "UNAUTHORIZED", "RECORDING_IN_PROGRESS",
                         "TIMEOUT", "INVALID_PARAM", "INVALID_VALUE", "UNSUPPORTED", "INVALID_ARGUMENTS",
                         "COMMAND_FAILED", "ACCESS_DENIED", "TAB_REQUIRED", "STALE_REFERENCE", "CANCELLED",
                         "READINESS_FAILED", "EXTRACT_FAILED", "BROWSER_FAILED", "BROWSER_BUSY", "PAGE_CHANGED"]
            IOSFrameSampler.diagnostic("observation-" + (known.contains(code) ? code : "OTHER"))
            #endif
            throw IOSWorkflowFailure("OBSERVATION_FAILED")
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
        throw IOSWorkflowFailure("TIMEOUT")
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
        guard result["ok"] as? Bool == true else {
            // The isolated-world fixed target function supplies these diagnostic enums.
            throw IOSWorkflowFailure(result["error"] as? String ?? "TARGET_FAILED",
                                     mayHaveCompleted: result["mayHaveCompleted"] as? Bool == true)
        }
    }

    private func interact(_ step: Body, action: String, index: Int) async throws {
        let target = step["target"] as? Body ?? [:]
        let document = tab.document
        let viewport = try await tab.viewport()
        let editing = action == "type" || action == "fill"
        let text = editing ? step["text"] as? String : nil
        let plan = workflow.pacedPlans[index]
        if plan != nil, let text { registerEditLiteral(text) }
        let consume = { [self] (result: Body) in
            consumeSensitivity(result, text: text)
        }
        let missing = { [self] in protectEditPrivacy(text: text) }
        if step["sensitive"] as? Bool == true { consume(["sensitive": true]) }
        let found = try await tab.target(
            target, refuseSensitive: workflow.capture != nil, consume: consume, missingResult: missing
        )
        try requireOK(found)
        guard let token = found["token"] as? String, let x = found["x"] as? Double, let y = found["y"] as? Double else {
            throw IOSWorkflowFailure("INVALID_TARGET")
        }
        if discardMedia { throw IOSWorkflowFailure("SENSITIVE_CAPTURE_REFUSED") }
        if let plan, !plan.clearFirst, plan.scalars.isEmpty {
            try requireOK(try await tab.target(
                target, token: token, refuseSensitive: workflow.capture != nil, consume: consume, missingResult: missing
            ))
            try await check()
            guard tab.document == document, viewport == (try await tab.viewport()) else {
                throw IOSWorkflowFailure("STALE_TARGET")
            }
            if workflow.stepScreenshots { _ = try await sampler?.step(index, document: document) }
            return
        }
        let point = viewport.displayPoint(CGPoint(x: x, y: y))
        try await movePointer(to: point)
        let settings = workflow.settings["tapIndicator"] as? Body ?? [:]
        let radius = CGFloat(settings["radius"] as? Double ?? 20) * viewport.bounds.width / viewport.visible.width
        try requireOK(try await tab.target(
            target, token: token, refuseSensitive: workflow.capture != nil, consume: consume, missingResult: missing
        ))
        if discardMedia { throw IOSWorkflowFailure("SENSITIVE_CAPTURE_REFUSED") }
        let hold = sampler?.recordsMotion == true
        let mark = { [presentation] in presentation.mark(at: point, radius: radius, settings: settings, held: hold) }
        if let sampler {
            try await sampler.markBeforeInput(workflow.stepScreenshots ? index : nil, document: document, prepare: mark)
            if hold { presentation.beginMarkerAnimation() }
        } else { mark() }
        try await check()
        let current = try await tab.viewport()
        guard tab.document == document, viewport == current else { throw IOSWorkflowFailure("STALE_TARGET") }
        if let plan {
            let context = PacedTarget(
                target: target,
                token: token,
                document: document,
                viewport: viewport,
                consume: consume,
                missing: missing
            )
            try await pacedEdit(plan, context: context)
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
            missingResult: missing
        )
        try requireOK(result)
        if discardMedia { throw IOSWorkflowFailure("SENSITIVE_CAPTURE_REFUSED", mayHaveCompleted: true) }
        do { try await check() } catch { throw IOSWorkflowFailure("INPUT_INTERRUPTED", mayHaveCompleted: true) }
    }

    private struct PacedTarget {
        let target: Body
        let token: String
        let document: String
        let viewport: IOSWorkflowTab.Viewport
        let consume: @MainActor (Body) -> Void
        let missing: @MainActor () -> Void
    }

    private func pacedEdit(_ plan: IOSPacedTypingPlan, context: PacedTarget) async throws {
        try await IOSPacedTypingExecutor.run(
            clearFirst: plan.clearFirst,
            scalars: plan.scalars,
            delayMs: plan.delayMs,
            apply: { [self] action, text, requireFocused in
                try await pacedMutation(action: action, text: text, requireFocused: requireFocused, context: context)
            },
            wait: { [self] delay in try await wait(milliseconds: delay) }
        )
    }

    private func pacedMutation(action: String, text: String, requireFocused: Bool, context: PacedTarget) async throws {
        try await check()
        guard tab.document == context.document, context.viewport == (try await tab.viewport()) else {
            throw IOSWorkflowFailure("STALE_TARGET")
        }
        let result = try await tab.target(
            context.target,
            token: context.token,
            edit: ["action": action, "text": text, "requireFocused": requireFocused],
            refuseSensitive: workflow.capture != nil,
            consume: context.consume,
            missingResult: context.missing
        )
        try requireOK(result)
        do {
            if discardMedia { throw IOSWorkflowFailure("SENSITIVE_CAPTURE_REFUSED", mayHaveCompleted: true) }
            try await check()
            let classification = try await tab.target(
                context.target,
                token: context.token,
                postMutation: true,
                refuseSensitive: workflow.capture != nil,
                consume: context.consume,
                missingResult: context.missing
            )
            try requireOK(classification)
            if discardMedia { throw IOSWorkflowFailure("SENSITIVE_CAPTURE_REFUSED", mayHaveCompleted: true) }
            guard classification["sensitivityKnown"] as? Bool == true else {
                throw IOSWorkflowFailure("INPUT_UNCERTAIN", mayHaveCompleted: true)
            }
            try await check()
        } catch let failure as IOSWorkflowFailure {
            throw IOSWorkflowFailure(failure.code, mayHaveCompleted: true)
        } catch {
            throw IOSWorkflowFailure("INPUT_INTERRUPTED", mayHaveCompleted: true)
        }
    }

    private func registerEditLiteral(_ text: String) {
        if !text.isEmpty, !secrets.contains(text) { secrets.append(text) }
    }

    private func consumeSensitivity(_ result: Body, text: String?) {
        #if DEBUG
        if result["error"] as? String == "INPUT_UNCERTAIN", let reason = result["focusFailure"] as? String {
            let known = ["document-focus", "target-focus", "identity", "viewport", "eligibility",
                         "budget", "geometry", "hit", "sensitivity", "unknown"]
            if known.contains(reason) { IOSFrameSampler.diagnostic("focus-" + reason) }
        }
        #endif
        guard result["sensitive"] as? Bool == true else { return }
        protectEditPrivacy(text: text)
    }

    private func protectEditPrivacy(text: String?) {
        if let text { registerEditLiteral(text) }
        if workflow.capture != nil { discardMedia = true }
    }

    private func movePointer(to point: CGPoint) async throws {
        guard let options = workflow.settings["pointer"] as? Body, options["enabled"] as? Bool == true else { return }
        let origin = presentation.lastPointer ?? CGPoint(x: max(0, point.x - 100), y: max(0, point.y - 70))
        let start = ProcessInfo.processInfo.systemUptime
        let duration = options["durationMs"] as? Double ?? 350
        let curve = options["curve"] as? String ?? "s"
        repeat {
            try await check()
            let progress = kelpie_script_progress((ProcessInfo.processInfo.systemUptime - start) * 1000, duration)
            presentation.move(to: ScriptOverlayDrawing.path(from: origin, to: point, progress: progress, curve: curve))
            if progress >= 1 { return }
            try await Task.sleep(nanoseconds: 16_000_000)
        } while true
    }
}
