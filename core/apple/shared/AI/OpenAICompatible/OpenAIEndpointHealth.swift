import Foundation

/// Live readiness of one endpoint + selected model. See the health table in
/// docs/api/ai-endpoints.md.
struct OpenAIEndpointHealth: Equatable, Sendable {
    enum State: String, Sendable {
        case unknown
        case unreachable
        case authFailed = "auth_failed"
        case loading
        case noModel = "no_model"
        case modelMissing = "model_missing"
        case ready
        case busy

        var isOnline: Bool {
            switch self {
            case .loading, .noModel, .modelMissing, .ready, .busy: return true
            case .unknown, .unreachable, .authFailed: return false
            }
        }
    }

    static let staleAfter: TimeInterval = 90

    var state: State = .unknown
    var message = "Not checked yet."
    var checkedAt: Date?
    var latencyMs: Int?
    var modelListed: Bool?
    var modelStatus: OpenAIModelInfo.Status?
    var generationVerifiedAt: Date?

    /// The state a caller should act on: stale results are never reported
    /// as live readiness, and in-flight work turns `ready` into `busy`.
    func effectiveState(now: Date, inFlight: Int) -> State {
        guard let checkedAt, now.timeIntervalSince(checkedAt) <= Self.staleAfter else { return .unknown }
        if state == .ready && inFlight > 0 { return .busy }
        return state
    }

    func publicJSON(now: Date = Date(), inFlight: Int = 0) -> [String: Any] {
        let effective = effectiveState(now: now, inFlight: inFlight)
        let stale = checkedAt.map { now.timeIntervalSince($0) > Self.staleAfter } ?? false
        return [
            "state": effective.rawValue,
            "online": effective.isOnline,
            "stale": stale,
            "message": stale ? "Last check is out of date (\(message))" : message,
            "checkedAt": checkedAt.map(Self.iso) ?? NSNull(),
            "latencyMs": latencyMs ?? NSNull(),
            "modelListed": modelListed ?? NSNull(),
            "modelStatus": modelStatus?.rawValue ?? NSNull(),
            "generationVerifiedAt": generationVerifiedAt.map(Self.iso) ?? NSNull(),
            "inFlight": inFlight
        ]
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

/// Pure transition logic from one discovery probe to the next health value.
enum OpenAIHealthEvaluator {
    static func evaluate(
        discovery: Result<[OpenAIModelInfo], OpenAIEndpointError>,
        selectedModel: String?,
        previous: OpenAIEndpointHealth,
        now: Date,
        latencyMs: Int?
    ) -> OpenAIEndpointHealth {
        var next = OpenAIEndpointHealth(checkedAt: now, latencyMs: latencyMs)
        switch discovery {
        case .success(let models):
            applyDiscovered(models, selectedModel: selectedModel, into: &next)
        case .failure(let error):
            applyFailure(error, selectedModel: selectedModel, previous: previous, into: &next)
        }
        // Generation proof only survives while the endpoint stays online.
        let wasOffline = previous.state == .unreachable || previous.state == .authFailed
        if next.state.isOnline && !wasOffline {
            next.generationVerifiedAt = previous.generationVerifiedAt
        }
        if next.state == .modelMissing, next.modelListed == nil, next.generationVerifiedAt != nil {
            next.state = .ready
            next.message = "Model discovery is unsupported; a generation test passed."
        }
        return next
    }

    private static func applyDiscovered(_ models: [OpenAIModelInfo], selectedModel: String?, into health: inout OpenAIEndpointHealth) {
        guard let selectedModel, !selectedModel.isEmpty else {
            health.state = .noModel
            health.message = models.isEmpty ? "Reachable, but the server lists no models." : "Reachable. Select a model."
            return
        }
        guard let model = models.first(where: { $0.id == selectedModel }) else {
            health.state = .modelMissing
            health.modelListed = false
            health.message = "Reachable, but \"\(selectedModel)\" is not in the server's model list."
            return
        }
        health.modelListed = true
        health.modelStatus = model.status
        switch model.status {
        case .loading, .unloaded:
            health.state = .loading
            health.message = "Reachable; the model is \(model.status?.rawValue ?? "loading")."
        case .loaded, nil:
            health.state = .ready
            health.message = "Ready."
        }
    }

    private static func applyFailure(
        _ error: OpenAIEndpointError,
        selectedModel: String?,
        previous: OpenAIEndpointHealth,
        into health: inout OpenAIEndpointHealth
    ) {
        health.message = error.message
        switch error {
        case .unreachable, .timeout, .redirectRefused, .cancelled:
            health.state = .unreachable
        case .authFailed:
            health.state = .authFailed
        case .loading:
            health.state = .loading
        case .discoveryUnsupported:
            if selectedModel?.isEmpty ?? true {
                health.state = .noModel
                health.message = "Reachable. Model discovery is unsupported; enter a model ID."
            } else {
                health.state = .modelMissing
                health.message = "Reachable. Model discovery is unsupported; run Test to prove the model can generate."
            }
        case .server(let status, _) where status == 429 || status == 503:
            health.state = .busy
        default:
            health.state = .unknown
        }
    }

    /// Polling cadence: modest while healthy, exponential backoff while failing.
    static func nextPollDelay(for state: OpenAIEndpointHealth.State, consecutiveFailures: Int) -> TimeInterval {
        if state.isOnline { return 30 }
        let schedule: [TimeInterval] = [5, 10, 20, 40, 60]
        return schedule[min(max(consecutiveFailures, 1), schedule.count) - 1]
    }
}
