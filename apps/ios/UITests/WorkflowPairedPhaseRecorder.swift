import Foundation

/// Bounded read-only observations; the first active run is checked against the terminal run by the test.
enum WorkflowPairedPhaseRecorder {
    typealias Body = [String: Any]

    static func observe(probe: WorkflowCaptureProbe, started: TimeInterval) async -> (String?, [Body]) {
        var runID: String?
        var samples: [Body] = []
        let allowedStates = ["running", "finalizing", "completed", "failed", "aborted"]
        let allowedErrors = ["TIMEOUT", "INPUT_UNCERTAIN", "CAPTURE_VIEWPORT_CHANGED", "CAPTURE_VIEWPORT_UNSTABLE",
                             "SCRIPT_ABORTED", "AUTHORIZATION_REVOKED", "TAB_CHANGED", "WEBVIEW_ERROR"]
        for _ in 0..<16 {
            if Task.isCancelled { break }
            let body: Body = runID.map { ["runId": $0] } ?? [:]
            if let status = try? await probe.request("/v1/get-script-status", body, timeout: 3),
               let candidate = status["runId"] as? String,
               let state = status["state"] as? String, allowedStates.contains(state) {
                if runID == nil, status["playing"] as? Bool == true { runID = candidate }
                if candidate == runID {
                    var sample: Body = ["atMs": Int((ProcessInfo.processInfo.systemUptime - started) * 1000),
                                        "state": state]
                    for key in ["actionIndex", "elapsedMs", "actionsExecuted"] {
                        if let value = status[key] as? Int, value >= 0, value <= 1_000_000 { sample[key] = value }
                    }
                    if let error = status["runError"] as? Body, let code = error["code"] as? String {
                        sample["error"] = allowedErrors.contains(code) ? code : "OTHER"
                    }
                    if let completed = status["mayHaveCompleted"] as? Bool { sample["mayHaveCompleted"] = completed }
                    samples.append(sample)
                    if status["playing"] as? Bool == false { break }
                }
            }
            do { try await Task.sleep(nanoseconds: 2_500_000_000) } catch { break }
        }
        return (runID, samples)
    }
}
