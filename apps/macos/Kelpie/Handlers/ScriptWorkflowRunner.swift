import AppKit

@MainActor
final class ScriptWorkflowRunner {
    typealias Body = [String: Any]
    let host: ScriptHandler
    private var runID: String?
    private var owner: String?
    private var started: TimeInterval = 0
    private var capture: ScriptCapture?
    private var actionIndex = 0
    private var totalActions = 0
    private var finalizing = false
    private var currentArtifacts: [Body] = []
    private var terminal: [(id: String, owner: String, value: Body)] = []

    init(host: ScriptHandler) { self.host = host }
    var isRunning: Bool { runID != nil }

    func control(_ method: String, _ body: Body, legacy: () -> Body) async -> Body {
        let grant = ScriptRequestOwner.current
        let authorized = await grant?.isCurrent() ?? false
        if method == "get-script-artifact" {
            guard let grant, authorized else { return denied() }
            return ScriptArtifactStore.shared.read(body, owner: grant.owner)
        }
        guard Set(body.keys).isSubset(of: ["runId"]), body["runId"] == nil ||
                (body["runId"] as? String).map({ !$0.isEmpty && $0.count <= 128 }) == true else {
            return ScriptWorkflowFailure("INVALID_PARAM").response
        }
        let requested = body["runId"] as? String
        if requested == nil, !isRunning {
            if method == "get-script-status", host.playbackState.statusResponse()["playing"] as? Bool != true,
               let grant, authorized, let latest = terminal.last(where: { $0.owner == grant.owner }) {
                return latest.value
            }
            return legacy()
        }
        if requested == nil, method == "get-script-status", grant?.owner != owner || !authorized {
            if let grant, authorized, let latest = terminal.last(where: { $0.owner == grant.owner }) { return latest.value }
            var idle = ScriptBoundWorkflow.capabilities
            idle["playing"] = false
            idle["state"] = "idle"
            return idle
        }
        guard let grant, authorized else { return denied() }
        if let requested, requested != runID {
            guard method == "get-script-status", let cached = terminal.last(where: { $0.id == requested && $0.owner == grant.owner }) else {
                return ScriptWorkflowFailure("RUN_NOT_FOUND").response
            }
            return cached.value
        }
        guard let runID, owner == grant.owner else { return ScriptWorkflowFailure("RUN_NOT_FOUND").response }
        if method == "abort-script" { _ = host.playbackState.requestAbort() }
        var status = ScriptBoundWorkflow.capabilities
        status["runId"] = runID
        if !currentArtifacts.isEmpty { status["artifacts"] = currentArtifacts }
        status["state"] = finalizing ? "finalizing" : "running"
        status["playing"] = true
        status["actionIndex"] = min(actionIndex, max(0, totalActions - 1))
        status["totalActions"] = totalActions
        status["elapsedMs"] = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        status["abortRequested"] = host.playbackState.isAbortRequested()
        return status
    }

    private func denied() -> Body { ScriptWorkflowFailure("UNAUTHORIZED").response }

    func play(_ body: Body) async -> Body {
        do {
            let workflow = try ScriptBoundWorkflow(body)
            guard let grant = ScriptRequestOwner.current, await grant.isCurrent(),
                  host.router.browserReferenceOwner == nil, host.context.remoteDocumentGuard == nil else { return denied() }
            let tab = try ScriptWorkflowTab(context: host.context, router: host.router, grant: grant, playback: host.playbackState, id: workflow.tabID)
            guard !ScriptRendererDeadline.isRetiring(tab.renderer), host.router.browserLease.begin() else {
                throw ScriptWorkflowFailure("BUSY")
            }
            let admitted = host.playbackState.start(totalActions: workflow.steps.count, continueOnError: false, holdSession: true)
            host.router.browserLease.end()
            guard admitted else { throw ScriptWorkflowFailure("RECORDING_IN_PROGRESS") }
            let id = UUID().uuidString
            runID = id
            owner = grant.owner
            started = ProcessInfo.processInfo.systemUptime
            actionIndex = 0
            totalActions = workflow.steps.count
            finalizing = false
            await host.context.exit3DInspectorIfNeeded(notify: true)
            await host.setRecordingMode(true)
            return await run(workflow, tab: tab, grant: grant, id: id)
        } catch { return (error as? ScriptWorkflowFailure ?? ScriptWorkflowFailure("INVALID_SCRIPT")).response }
    }

    private func requireCurrent(tab: ScriptWorkflowTab, grant: ScriptRequestOwner) async throws {
        try await tab.check()
        if let failure = capture?.failure { throw ScriptWorkflowFailure(failure) }
    }

    private func run(_ workflow: ScriptBoundWorkflow, tab: ScriptWorkflowTab, grant: ScriptRequestOwner, id: String) async -> Body {
        var issue: ScriptWorkflowFailure?
        var presentation: ScriptPresentation?
        var actions: ScriptWorkflowActions?
        var outputs: Body = [:]
        let check = { @MainActor [self] in try await requireCurrent(tab: tab, grant: grant) }
        do {
            try await tab.waitForLayout()
            let scene = ScriptPresentation(renderer: tab.renderer)
            presentation = scene
            let executor = ScriptWorkflowActions(workflow: workflow, tab: tab, presentation: scene, router: host.router, check: check)
            actions = executor
            if let settings = workflow.capture {
                let capture = try ScriptCapture(tab: tab, presentation: scene, options: settings, runID: id)
                self.capture = capture
                executor.capture = capture
                try await capture.start()
            }
            for (index, step) in workflow.steps.enumerated() {
                host.playbackState.updateCurrentAction(index: index, action: step["action"] as? String ?? "")
                try await executor.execute(step, index: index)
                host.playbackState.recordSuccess(index: index)
                actionIndex = index + 1
                if index + 1 < workflow.steps.count { try await executor.wait(milliseconds: workflow.settings["defaultWaitBetweenActions"] as? Int ?? 0) }
            }
            if capture?.hasMovies == true, let end = scene.markerEnd {
                try await executor.wait(milliseconds: Int(max(0, end - ProcessInfo.processInfo.systemUptime) * 1000))
            }
        } catch { issue = error as? ScriptWorkflowFailure ?? ScriptWorkflowFailure("WORKFLOW_FAILED") }
        finalizing = true
        if let actions {
            do { outputs = try ScriptOutputRedaction.redact(actions.outputs, actions: workflow.steps, secrets: actions.secrets) } catch { issue = ScriptWorkflowFailure("OUTPUT_REDACTION_FAILED") }
        }
        var artifacts = await capture?.finish(partial: issue != nil, discard: issue?.code == "SENSITIVE_CAPTURE_REFUSED") ?? []
        currentArtifacts = artifacts
        if issue == nil, let failure = capture?.failure { issue = ScriptWorkflowFailure(failure) }
        await ScriptRendererDeadline.waitForRetirement(tab.renderer)
        await tab.resetTargets()
        await ScriptRendererDeadline.waitForRetirement(tab.renderer)
        presentation?.stop()
        await host.setRecordingMode(false)
        if host.playbackState.isAbortRequested() {
            issue = ScriptWorkflowFailure("SCRIPT_ABORTED", mayHaveCompleted: issue?.mayHaveCompleted ?? false)
        }
        if issue != nil { artifacts = artifacts.map { $0.merging(["partial": true]) { _, new in new } } }
        currentArtifacts = artifacts
        let response = finish(id: id, owner: grant.owner, issue: issue, outputs: outputs, artifacts: artifacts)
        host.playbackState.releaseHeldSession()
        guard await grant.isCurrent() else { return denied() }
        return response
    }

    private func finish(id: String, owner runOwner: String, issue: ScriptWorkflowFailure?, outputs: Body, artifacts: [Body]) -> Body {
        if let issue { _ = host.playbackState.finishFatalFailure(code: issue.code, message: "Workflow stopped") } else { _ = host.playbackState.finishSuccess() }
        var result = issue?.response ?? ["success": true]
        result["runId"] = id
        result["state"] = issue == nil ? "completed" : issue?.code == "SCRIPT_ABORTED" ? "aborted" : "failed"
        result["playing"] = false
        result["actionsExecuted"] = actionIndex
        result["totalDurationMs"] = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        result["inputGuarantee"] = "synthetic-coordinate"
        result["artifacts"] = artifacts
        var status = ScriptBoundWorkflow.capabilities
        status["runId"] = id
        status["playing"] = false
        status["state"] = result["state"]
        status["runSuccess"] = result["success"]
        status["runError"] = result["error"]
        status["mayHaveCompleted"] = result["mayHaveCompleted"]
        status["actionIndex"] = min(actionIndex, max(0, totalActions - 1))
        status["totalActions"] = totalActions
        status["totalDurationMs"] = result["totalDurationMs"]
        status["artifacts"] = artifacts
        terminal.append((id, runOwner, status))
        if terminal.count > 8 { terminal.removeFirst() }
        result["outputs"] = outputs
        runID = nil
        finalizing = false
        owner = nil
        capture = nil
        currentArtifacts = []
        return result
    }
}
