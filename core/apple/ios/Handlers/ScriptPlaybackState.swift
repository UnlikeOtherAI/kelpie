import Foundation

struct ScriptPlaybackIssue: Sendable {
    let index: Int
    let action: String
    let code: String
    let message: String
    let skipped: Bool

    var dictionary: [String: Any] {
        var result: [String: Any] = [
            "index": index,
            "action": action,
            "error": [
                "code": code,
                "message": message
            ]
        ]
        if skipped {
            result["skipped"] = true
        }
        return result
    }
}

struct ScriptPlaybackScreenshot: Sendable {
    let index: Int
    let file: String
    let width: Int
    let height: Int

    var dictionary: [String: Any] {
        [
            "index": index,
            "file": file,
            "width": width,
            "height": height
        ]
    }
}

final class ScriptPlaybackState: @unchecked Sendable {
    private struct Session: Sendable {
        let totalActions: Int
        let continueOnError: Bool
        let startedAt: Date
        var currentActionIndex: Int?
        var currentActionName: String?
        var actionsExecuted = 0
        var actionsSucceeded = 0
        var abortRequested = false
        var issues: [ScriptPlaybackIssue] = []
        var screenshots: [ScriptPlaybackScreenshot] = []
    }

    private static let allowedMethodsWhileRecording: Set<String> = [
        "abort-script",
        "get-script-status"
    ]

    private let lock = NSLock()
    private var session: Session?

    func start(totalActions: Int, continueOnError: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard session == nil else { return false }
        session = Session(
            totalActions: totalActions,
            continueOnError: continueOnError,
            startedAt: Date()
        )
        return true
    }

    func updateCurrentAction(index: Int, action: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var session else { return }
        session.currentActionIndex = index
        session.currentActionName = action
        self.session = session
    }

    func recordSuccess(index: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard var session else { return }
        session.actionsExecuted = max(session.actionsExecuted, index + 1)
        session.actionsSucceeded += 1
        self.session = session
    }

    func recordFailure(index: Int, action: String, code: String, message: String, skipped: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard var session else { return }
        session.actionsExecuted = max(session.actionsExecuted, index + 1)
        session.issues.append(
            ScriptPlaybackIssue(
                index: index,
                action: action,
                code: code,
                message: message,
                skipped: skipped
            )
        )
        self.session = session
    }

    func addScreenshot(index: Int, file: String, width: Int, height: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard var session else { return }
        session.screenshots.append(
            ScriptPlaybackScreenshot(
                index: index,
                file: file,
                width: width,
                height: height
            )
        )
        self.session = session
    }

    func isAbortRequested() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return session?.abortRequested ?? false
    }

    func requestAbort() -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        guard var session else { return nil }
        session.abortRequested = true
        self.session = session
        return buildResult(success: false, aborted: true, session: session, topLevelError: nil)
    }

    func finishSuccess() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        guard let session else { return ["success": true] }
        self.session = nil
        if !session.issues.isEmpty {
            let count = session.issues.count
            return buildResult(
                success: false,
                aborted: false,
                session: session,
                topLevelError: (
                    code: "SCRIPT_PARTIAL_FAILURE",
                    message: "\(count) of \(session.totalActions) actions failed"
                )
            )
        }
        return buildResult(success: true, aborted: false, session: session, topLevelError: nil)
    }

    func finishFatalFailure(code: String, message: String) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        guard let session else {
            return errorResponse(code: code, message: message)
        }
        self.session = nil
        return buildResult(
            success: false,
            aborted: false,
            session: session,
            topLevelError: (code: code, message: message)
        )
    }

    func finishAborted() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        guard let session else {
            return ["success": false, "aborted": true]
        }
        self.session = nil
        return buildResult(success: false, aborted: true, session: session, topLevelError: nil)
    }

    func statusResponse() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        guard let session else { return ["playing": false] }
        return [
            "playing": true,
            "currentAction": session.currentActionIndex as Any,
            "currentActionName": session.currentActionName as Any,
            "totalActions": session.totalActions,
            "elapsedMs": elapsedMilliseconds(since: session.startedAt),
            "abortRequested": session.abortRequested
        ]
    }

    func recordingError(for method: String) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        guard session != nil else { return nil }
        guard !Self.allowedMethodsWhileRecording.contains(method) else { return nil }
        return errorResponse(
            code: "RECORDING_IN_PROGRESS",
            message: "Script is playing. Call abort-script to stop."
        )
    }

    private func buildResult(
        success: Bool,
        aborted: Bool,
        session: Session,
        topLevelError: (code: String, message: String)?
    ) -> [String: Any] {
        var result: [String: Any] = [
            "success": success,
            "actionsExecuted": session.actionsExecuted,
            "totalDurationMs": elapsedMilliseconds(since: session.startedAt),
            "errors": session.issues.map(\.dictionary),
            "screenshots": session.screenshots.map(\.dictionary)
        ]
        if session.continueOnError {
            result["actionsSucceeded"] = session.actionsSucceeded
        }
        if aborted {
            result["aborted"] = true
        }
        if let topLevelError {
            result["error"] = [
                "code": topLevelError.code,
                "message": topLevelError.message
            ]
        }
        return result
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
