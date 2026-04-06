import Foundation

struct ScriptHandler {
    let context: HandlerContext
    let router: Router
    let playbackState: ScriptPlaybackState
    let setRecordingMode: @Sendable (Bool) async -> Void

    func register(on router: Router) {
        router.register("play-script") { body in await playScript(body) }
        router.register("abort-script") { _ in abortScript() }
        router.register("get-script-status") { _ in getScriptStatus() }
    }

    @MainActor
    private func playScript(_ body: [String: Any]) async -> [String: Any] {
        guard let actions = body["actions"] as? [[String: Any]], !actions.isEmpty else {
            return errorResponse(code: "MISSING_PARAM", message: "actions is required")
        }
        let continueOnError = body["continueOnError"] as? Bool ?? false
        let defaultWaitBetweenActions = body["defaultWaitBetweenActions"] as? Int ?? 0
        let overlayColor = body["overlayColor"] as? String ?? "#3B82F6"

        guard playbackState.start(totalActions: actions.count, continueOnError: continueOnError) else {
            return errorResponse(code: "RECORDING_IN_PROGRESS", message: "Script is playing. Call abort-script to stop.")
        }

        await context.exit3DInspectorIfNeeded(notify: true)
        await setRecordingMode(true)
        let result = await runScript(
            actions: actions,
            overlayColor: overlayColor,
            defaultWaitBetweenActions: defaultWaitBetweenActions,
            continueOnError: continueOnError
        )
        await setRecordingMode(false)
        return result
    }

    private func abortScript() -> [String: Any] {
        playbackState.requestAbort()
            ?? errorResponse(code: "NO_SCRIPT_RUNNING", message: "No script is currently playing")
    }

    private func getScriptStatus() -> [String: Any] {
        playbackState.statusResponse()
    }

    @MainActor
    private func runScript(
        actions: [[String: Any]],
        overlayColor: String,
        defaultWaitBetweenActions: Int,
        continueOnError: Bool
    ) async -> [String: Any] {
        for (index, action) in actions.enumerated() {
            if playbackState.isAbortRequested() {
                return playbackState.finishAborted()
            }

            guard let actionName = action["action"] as? String, !actionName.isEmpty else {
                playbackState.recordFailure(
                    index: index,
                    action: "unknown",
                    code: "INVALID_ACTION",
                    message: "Each action requires an action name",
                    skipped: false
                )
                return playbackState.finishFatalFailure(
                    code: "INVALID_ACTION",
                    message: "Each action requires an action name"
                )
            }

            playbackState.updateCurrentAction(index: index, action: actionName)
            let response = await executeAction(action, actionName: actionName, overlayColor: overlayColor)
            if isAbortResponse(response) {
                return playbackState.finishAborted()
            }
            let succeeded = response["success"] as? Bool ?? false

            if actionName == "screenshot",
               succeeded,
               let screenshot = saveScreenshot(from: response, index: index) {
                playbackState.addScreenshot(
                    index: screenshot.index,
                    file: screenshot.file,
                    width: screenshot.width,
                    height: screenshot.height
                )
            }

            if succeeded {
                playbackState.recordSuccess(index: index)
            } else {
                let error = errorDetails(from: response)
                playbackState.recordFailure(
                    index: index,
                    action: actionName,
                    code: error.code,
                    message: error.message,
                    skipped: continueOnError
                )
                if !continueOnError {
                    return playbackState.finishFatalFailure(code: error.code, message: error.message)
                }
            }

            if playbackState.isAbortRequested() {
                return playbackState.finishAborted()
            }

            let shouldPause = defaultWaitBetweenActions > 0 &&
                index < actions.count - 1 &&
                !["wait", "wait-for-element", "wait-for-navigation"].contains(actions[index + 1]["action"] as? String ?? "")
            if shouldPause {
                if !(await sleepWithAbortCheck(milliseconds: defaultWaitBetweenActions)) {
                    return playbackState.finishAborted()
                }
            }
        }

        return playbackState.finishSuccess()
    }

    @MainActor
    private func executeAction(
        _ action: [String: Any],
        actionName: String,
        overlayColor: String
    ) async -> [String: Any] {
        switch actionName {
        case "wait":
            guard let milliseconds = action["ms"] as? Int else {
                return errorResponse(code: "MISSING_PARAM", message: "ms is required")
            }
            if !(await sleepWithAbortCheck(milliseconds: milliseconds)) {
                return abortResponse()
            }
            return successResponse(["waitedMs": milliseconds])
        case "wait-for-element":
            return await waitForElement(action)
        case "wait-for-navigation":
            return await waitForNavigation(action)
        default:
            let method = forwardedMethod(for: actionName)
            guard !method.isEmpty else {
                return errorResponse(code: "INVALID_ACTION", message: "Unsupported action: \(actionName)")
            }
            let body = forwardedBody(for: action, actionName: actionName, overlayColor: overlayColor)
            return await router.handle(method: method, body: body, bypassRecordingGate: true).json
        }
    }

    private func forwardedMethod(for actionName: String) -> String {
        switch actionName {
        case "commentary":
            return "show-commentary"
        default:
            return actionName
        }
    }

    private func forwardedBody(
        for action: [String: Any],
        actionName: String,
        overlayColor: String
    ) -> [String: Any] {
        var body = action
        body.removeValue(forKey: "action")
        let colorActions: Set<String> = [
            "click", "tap", "fill", "type", "select-option", "check", "uncheck", "swipe"
        ]
        if colorActions.contains(actionName), body["color"] == nil {
            body["color"] = overlayColor
        }
        return body
    }

    @MainActor
    private func waitForElement(_ body: [String: Any]) async -> [String: Any] {
        guard let selector = body["selector"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "selector is required")
        }
        let timeout = body["timeout"] as? Int ?? 5000
        let state = body["state"] as? String ?? "visible"
        let start = Date()
        let iterations = max(timeout / 100, 1)

        for _ in 0..<iterations {
            if playbackState.isAbortRequested() {
                return abortResponse()
            }
            let js = """
            (function() {
                var el = document.querySelector('\(JSEscape.string(selector))');
                if (!el) return null;
                var rect = el.getBoundingClientRect();
                var visible = rect.width > 0 && rect.height > 0;
                return {tag: el.tagName.toLowerCase(), classes: Array.from(el.classList), visible: visible};
            })()
            """
            if let result = try? await context.evaluateJSReturningJSON(js), !result.isEmpty {
                let visible = result["visible"] as? Bool ?? false
                let matches = state == "attached" || (state == "visible" && visible) || (state == "hidden" && !visible)
                if matches {
                    return successResponse([
                        "element": result,
                        "waitTime": Int(Date().timeIntervalSince(start) * 1000)
                    ])
                }
            }
            if !(await sleepWithAbortCheck(milliseconds: 100)) {
                return abortResponse()
            }
        }
        return errorResponse(code: "TIMEOUT", message: "Element did not reach state '\(state)' within \(timeout)ms")
    }

    @MainActor
    private func waitForNavigation(_ body: [String: Any]) async -> [String: Any] {
        guard context.renderer != nil else {
            return errorResponse(code: "NO_WEBVIEW", message: "No WebView")
        }
        let timeout = body["timeout"] as? Int ?? 10000
        let start = Date()
        var observedLoading = context.isLoadingPage

        for _ in 0..<(max(timeout / 100, 1)) {
            if playbackState.isAbortRequested() {
                return abortResponse()
            }
            let isLoading = context.isLoadingPage
            if isLoading {
                observedLoading = true
            }
            if observedLoading, !isLoading {
                return successResponse([
                    "url": context.currentURL?.absoluteString ?? "",
                    "title": context.currentTitle,
                    "loadTime": Int(Date().timeIntervalSince(start) * 1000)
                ])
            }
            if !(await sleepWithAbortCheck(milliseconds: 100)) {
                return abortResponse()
            }
        }
        return errorResponse(code: "TIMEOUT", message: "Navigation did not complete within \(timeout)ms")
    }

    private func abortResponse() -> [String: Any] {
        [
            "success": false,
            "aborted": true,
            "error": [
                "code": "SCRIPT_ABORTED",
                "message": "Script playback was aborted"
            ]
        ]
    }

    private func isAbortResponse(_ response: [String: Any]) -> Bool {
        response["aborted"] as? Bool == true
    }

    private func sleepWithAbortCheck(milliseconds: Int) async -> Bool {
        let total = max(milliseconds, 0)
        var elapsed = 0
        while elapsed < total {
            if playbackState.isAbortRequested() {
                return false
            }
            let slice = min(50, total - elapsed)
            try? await Task.sleep(nanoseconds: UInt64(slice) * 1_000_000)
            elapsed += slice
        }
        return !playbackState.isAbortRequested()
    }

    private func saveScreenshot(from response: [String: Any], index: Int) -> ScriptPlaybackScreenshot? {
        guard let image = response["image"] as? String,
              let data = Data(base64Encoded: image) else {
            return nil
        }
        let format = (response["format"] as? String ?? "png").lowercased()
        let ext = format == "jpeg" ? "jpg" : "png"
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("kelpie-script-\(index)-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: file)
            return ScriptPlaybackScreenshot(
                index: index,
                file: file.path,
                width: intValue(response["width"]),
                height: intValue(response["height"])
            )
        } catch {
            return nil
        }
    }

    private func errorDetails(from response: [String: Any]) -> (code: String, message: String) {
        guard let error = response["error"] as? [String: Any] else {
            return ("SCRIPT_ACTION_FAILED", "Script action failed")
        }
        return (
            error["code"] as? String ?? "SCRIPT_ACTION_FAILED",
            error["message"] as? String ?? "Script action failed"
        )
    }

    private func intValue(_ value: Any?) -> Int {
        switch value {
        case let int as Int:
            return int
        case let double as Double:
            return Int(double)
        default:
            return 0
        }
    }
}
