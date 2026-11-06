import Foundation

/// Bounded read-only observations; the first active run is checked against the terminal run by the test.
enum WorkflowPairedPhaseRecorder {
    typealias Body = [String: Any]

    struct Sample: Codable, Sendable {
        let atMs: Int
        let state: String
        let actionIndex: Int?
        let elapsedMs: Int?
        let actionsExecuted: Int?
        let error: String?
        let mayHaveCompleted: Bool?
    }

    struct Observation: Sendable {
        let runID: String?
        let samples: [Sample]
        let attempts: Int
    }

    struct Report: Codable, Sendable {
        let requestStartMs: Int
        let stopObserved: Bool?
        let stopObservedMs: Int?
        let responseMs: Int
        let transport: String
        let runMatched: Bool
        let terminalCode: String
        let mayHaveCompleted: Bool?
        let actionsExecuted: Int?
        let attempts: Int
        let observations: [Sample]
        let limitation: String
    }

    static func observe(probe: WorkflowCaptureProbe, started: TimeInterval) async -> Observation {
        var runID: String?
        var samples: [Sample] = []
        var attempts = 0
        let allowedStates = ["running", "finalizing", "completed", "failed", "aborted"]
        let allowedErrors = ["TIMEOUT", "INPUT_UNCERTAIN", "CAPTURE_VIEWPORT_CHANGED", "CAPTURE_VIEWPORT_UNSTABLE",
                             "SCRIPT_ABORTED", "AUTHORIZATION_REVOKED", "TAB_CHANGED", "WEBVIEW_ERROR"]
        for _ in 0..<16 {
            if Task.isCancelled { break }
            attempts += 1
            let body: Body = runID.map { ["runId": $0] } ?? [:]
            if let status = try? await probe.request("/v1/get-script-status", body, timeout: 3),
               let candidate = status["runId"] as? String,
               let state = status["state"] as? String, allowedStates.contains(state) {
                if runID == nil, status["playing"] as? Bool == true { runID = candidate }
                if candidate == runID {
                    func number(_ key: String) -> Int? {
                        guard let value = status[key] as? Int, value >= 0, value <= 1_000_000 else { return nil }
                        return value
                    }
                    let code = (status["runError"] as? Body)?["code"] as? String
                    samples.append(Sample(atMs: Int((ProcessInfo.processInfo.systemUptime - started) * 1000),
                                          state: state, actionIndex: number("actionIndex"), elapsedMs: number("elapsedMs"),
                                          actionsExecuted: number("actionsExecuted"),
                                          error: code.map { allowedErrors.contains($0) ? $0 : "OTHER" },
                                          mayHaveCompleted: status["mayHaveCompleted"] as? Bool))
                    if status["playing"] as? Bool == false { break }
                }
            }
            do { try await Task.sleep(nanoseconds: 2_500_000_000) } catch { break }
        }
        return Observation(runID: runID, samples: samples, attempts: attempts)
    }
}
