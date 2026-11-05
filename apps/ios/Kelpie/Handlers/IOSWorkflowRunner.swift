import UIKit

@MainActor
final class IOSWorkflowRunner {
    typealias Body = [String: Any]
    let host: ScriptHandler
    private var runID: String?
    private var owner: String?
    private var started: TimeInterval = 0
    private var sampler: IOSFrameSampler?
    private var actionIndex = 0
    private var totalActions = 0
    private var finalizing = false
    private var terminal: [(id: String, owner: String, value: Body)] = []
    private var retiringPresentation: IOSWorkflowPresentation?
    private var retirementTask: Task<Void, Never>?

    init(host: ScriptHandler) { self.host = host }
    var isRunning: Bool { runID != nil }

    func control(_ method: String, _ body: Body, legacy: () -> Body) async -> Body {
        let grant = IOSScriptGrant.current
        let authorized = await grant?.isCurrent() ?? false
        if method == "get-script-artifact" {
            guard let grant, authorized else { return denied() }
            return ScriptArtifactStore.shared.read(
                body,
                owner: grant.owner,
                blockedRunID: owner == grant.owner ? runID : nil
            )
        }
        guard Set(body.keys).isSubset(of: ["runId"]), body["runId"] == nil ||
                (body["runId"] as? String).map({ !$0.isEmpty && $0.count <= 128 }) == true else {
            return IOSWorkflowFailure("INVALID_PARAM").response
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
            var idle = IOSBoundWorkflow.capabilities
            idle["playing"] = false
            idle["state"] = "idle"
            return idle
        }
        guard let grant, authorized else { return denied() }
        if let requested, requested != runID {
            guard method == "get-script-status", let cached = terminal.last(where: { $0.id == requested && $0.owner == grant.owner }) else {
                return IOSWorkflowFailure("RUN_NOT_FOUND").response
            }
            return cached.value
        }
        guard let runID, owner == grant.owner else { return IOSWorkflowFailure("RUN_NOT_FOUND").response }
        if method == "abort-script" { _ = host.playbackState.requestAbort() }
        var status = IOSBoundWorkflow.capabilities
        status["runId"] = runID
        status["artifacts"] = [Body]()
        status["state"] = finalizing ? "finalizing" : "running"
        status["playing"] = true
        status["actionIndex"] = min(actionIndex, max(0, totalActions - 1))
        status["totalActions"] = totalActions
        status["elapsedMs"] = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        status["abortRequested"] = host.playbackState.isAbortRequested()
        return status
    }

    private func denied() -> Body { IOSWorkflowFailure("UNAUTHORIZED").response }

    func play(_ body: Body) async -> Body {
        do {
            let workflow = try IOSBoundWorkflow(body)
            guard let grant = IOSScriptGrant.current, await grant.isCurrent(),
                  host.router.browserReferenceOwner == nil, host.context.remoteDocumentGuard == nil else { return denied() }
            let tab = try IOSWorkflowTab(context: host.context, router: host.router, grant: grant, playback: host.playbackState, id: workflow.tabID)
            guard !IOSRendererDeadline.isRetiring(tab.view), host.router.browserLease.begin() else {
                throw IOSWorkflowFailure("BUSY")
            }
            let admitted = host.playbackState.start(totalActions: workflow.steps.count, continueOnError: false)
            host.router.browserLease.end()
            guard admitted else { throw IOSWorkflowFailure("RECORDING_IN_PROGRESS") }
            clearRetiringPresentation()
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
        } catch { return (error as? IOSWorkflowFailure ?? IOSWorkflowFailure("INVALID_SCRIPT")).response }
    }

    private func requireCurrent(tab: IOSWorkflowTab, grant: IOSScriptGrant) async throws {
        guard !Task.isCancelled, !host.playbackState.isAbortRequested() else { throw IOSWorkflowFailure("SCRIPT_ABORTED") }
        guard await grant.isCurrent() else { throw IOSWorkflowFailure("AUTHORIZATION_REVOKED") }
        guard !host.playbackState.isAbortRequested() else { throw IOSWorkflowFailure("SCRIPT_ABORTED") }
        guard ProcessInfo.processInfo.systemUptime - started < 300 else { throw IOSWorkflowFailure("TIMEOUT") }
        try tab.requireCurrent()
        guard tab.view.window?.windowScene?.activationState == .foregroundActive else { throw IOSWorkflowFailure("TAB_NOT_VISIBLE") }
        if let failure = sampler?.failure { throw failure }
        try sampler?.checkTime()
    }

    private func run(_ workflow: IOSBoundWorkflow, tab: IOSWorkflowTab, grant: IOSScriptGrant, id: String) async -> Body {
        var issue: IOSWorkflowFailure?
        var media: IOSWorkflowMedia?
        var presentation: IOSWorkflowPresentation?
        var actions: IOSWorkflowActions?
        var outputs: Body = [:]
        let check = { @MainActor [self] in try await requireCurrent(tab: tab, grant: grant) }
        do {
            try await tab.waitForRecordingLayout(check: check)
            let scene = try IOSWorkflowPresentation(tab: tab)
            presentation = scene
            let executor = IOSWorkflowActions(workflow: workflow, tab: tab, presentation: scene, router: host.router, check: check)
            actions = executor
            if let settings = workflow.capture {
                let sink = try IOSWorkflowMedia(runID: id, owner: grant.owner, settings: settings)
                media = sink
                let sampler = IOSFrameSampler(tab: tab, presentation: scene, settings: settings, check: check, receive: sink.receive)
                self.sampler = sampler
                executor.sampler = sampler
                try await sampler.start()
            }
            for (index, step) in workflow.steps.enumerated() {
                host.playbackState.updateCurrentAction(index: index, action: step["action"] as? String ?? "")
                try await executor.execute(step, index: index)
                host.playbackState.recordSuccess(index: index)
                actionIndex = index + 1
                if index + 1 < workflow.steps.count { try await executor.wait(milliseconds: workflow.settings["defaultWaitBetweenActions"] as? Int ?? 0) }
            }
            if let sampler, sampler.recordsMotion {
                if let end = scene.markerEnd {
                    try await executor.wait(milliseconds: Int(max(0, end - ProcessInfo.processInfo.systemUptime) * 1000))
                }
                while !(try await sampler.step(nil)) { try sampler.checkTime() }
            }
        } catch { issue = error as? IOSWorkflowFailure ?? IOSWorkflowFailure("WORKFLOW_FAILED") }
        finalizing = true
        await sampler?.stop()
        if issue == nil, !host.playbackState.isAbortRequested(), sampler?.recordsMotion != true, let presentation {
            retirePresentation(presentation, tab: tab, grant: grant)
        } else {
            presentation?.finish()
        }
        // Late renderer results may still classify an attempted edit as sensitive.
        // Stop sampling first; the existing retirement fence owns callback completion.
        await IOSRendererDeadline.waitForRetirement(tab.view)
        var discardMedia = actions?.discardMedia == true || issue?.code == "SENSITIVE_CAPTURE_REFUSED"
        if let actions {
            do {
                outputs = try ScriptOutputRedaction.redact(actions.outputs, actions: workflow.steps, secrets: actions.secrets)
            } catch {
                discardMedia = true
                if issue == nil { issue = IOSWorkflowFailure("OUTPUT_REDACTION_FAILED") }
            }
        }
        let artifacts = await media?.finish(
            elapsed: sampler?.elapsed ?? 0,
            dropped: sampler?.dropped ?? 0,
            partial: issue != nil,
            discard: discardMedia,
            isAborted: { [state = host.playbackState] in state.isAbortRequested() }
        ) ?? []
        await tab.resetTargets()
        await IOSRendererDeadline.waitForRetirement(tab.view)
        await host.setRecordingMode(false)
        issue = IOSWorkflowFailure.terminal(
            action: issue,
            capture: media?.failure ?? sampler?.failure,
            stopRequested: host.playbackState.isAbortRequested()
        )
        if issue != nil { clearRetiringPresentation(ifOwned: presentation) }
        let response = finish(id: id, owner: grant.owner, issue: issue, outputs: outputs, artifacts: artifacts)
        guard await grant.isCurrent() else { clearRetiringPresentation(ifOwned: presentation); return denied() }
        return response
    }

    private func clearRetiringPresentation() {
        retirementTask?.cancel()
        retirementTask = nil
        retiringPresentation?.finish()
        retiringPresentation = nil
    }

    private func clearRetiringPresentation(ifOwned presentation: IOSWorkflowPresentation?) {
        guard let presentation, retiringPresentation === presentation else { return }
        clearRetiringPresentation()
    }

    private func retirePresentation(_ presentation: IOSWorkflowPresentation, tab: IOSWorkflowTab, grant: IOSScriptGrant) {
        guard let end = presentation.markerEnd, end > ProcessInfo.processInfo.systemUptime,
              let window = tab.view.window else { presentation.finish(); return }
        let document = tab.document
        retiringPresentation = presentation
        presentation.beginRetirement(window: window, document: document, deadline: end) { [weak self, weak presentation] in
            self?.clearRetiringPresentation(ifOwned: presentation)
        }
        guard retiringPresentation === presentation else { return }
        retirementTask = Task { @MainActor [weak self, presentation, weak window] in
            while !Task.isCancelled && ProcessInfo.processInfo.systemUptime < end {
                guard let window, tab.view.window === window, window.windowScene?.activationState == .foregroundActive,
                      tab.document == document, (try? tab.requireCurrent()) != nil else {
                    #if DEBUG
                    presentation.retirementDiagnostic("owner", deadline: end)
                    #endif
                    break
                }
                guard await grant.isCurrent() else {
                    #if DEBUG
                    presentation.retirementDiagnostic("grant", deadline: end)
                    #endif
                    break
                }
                let remaining = end - ProcessInfo.processInfo.systemUptime
                if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(min(0.025, remaining) * 1_000_000_000)) }
            }
            guard !Task.isCancelled else { return }
            presentation.finish()
            guard self?.retiringPresentation === presentation else { return }
            self?.retiringPresentation = nil
            self?.retirementTask = nil
        }
    }

    private func finish(id: String, owner runOwner: String, issue: IOSWorkflowFailure?, outputs: Body, artifacts: [Body]) -> Body {
        if let issue { _ = host.playbackState.finishFatalFailure(code: issue.code, message: "Workflow stopped") } else { _ = host.playbackState.finishSuccess() }
        var result = issue?.response ?? ["success": true]
        result["runId"] = id
        result["state"] = issue == nil ? "completed" : issue?.code == "SCRIPT_ABORTED" ? "aborted" : "failed"
        result["playing"] = false
        result["actionsExecuted"] = actionIndex
        result["totalDurationMs"] = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        result["inputGuarantee"] = "synthetic-coordinate"
        result["artifacts"] = artifacts
        var status = IOSBoundWorkflow.capabilities
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
        sampler = nil
        return result
    }
}
