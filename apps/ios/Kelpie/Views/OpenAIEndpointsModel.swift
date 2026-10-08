import Combine
import Foundation

/// Settings-screen view model for OpenAI-compatible endpoints. It reads and
/// mutates `OpenAIEndpointService` (the single owner of endpoints, selection
/// and health) and never keeps its own copy beyond what is on screen.
@MainActor
final class OpenAIEndpointsModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let config: OpenAIEndpointConfig
        let hasApiKey: Bool
        let isActive: Bool
        /// Effective state: stale results read as `unknown`.
        let health: OpenAIEndpointHealth.State
        let healthMessage: String

        var id: String { config.id }
        var isLoopback: Bool { config.url?.isLoopback ?? false }
    }

    @Published private(set) var rows: [Row] = []
    /// Outcome of the last action per endpoint id, shown under the actions.
    @Published private(set) var statusMessages: [String: String] = [:]
    @Published private(set) var busyIds: Set<String> = []

    private let service: OpenAIEndpointService
    private var cancellable: AnyCancellable?

    init(service: OpenAIEndpointService = .shared) {
        self.service = service
        cancellable = NotificationCenter.default.publisher(for: .openAIEndpointsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadSoon() }
    }

    func row(_ id: String) -> Row? {
        rows.first { $0.id == id }
    }

    func reloadSoon() {
        Task { await reload() }
    }

    func reload() async {
        let configs = await service.endpoints
        let activeId = await service.activeEndpoint()?.config.id
        let now = Date()
        var next: [Row] = []
        for config in configs {
            let health = await service.health[config.id] ?? OpenAIEndpointHealth()
            let inFlight = await service.inFlight[config.id] ?? 0
            next.append(Row(
                config: config,
                hasApiKey: await service.hasApiKey(config),
                isActive: config.id == activeId,
                health: health.effectiveState(now: now, inFlight: inFlight),
                healthMessage: health.message
            ))
        }
        if next != rows { rows = next }
    }

    // MARK: - Actions

    /// Saves without connecting. Returns the saved endpoint or an error message.
    func save(_ draft: OpenAIEndpointService.Draft) async -> Result<OpenAIEndpointConfig, OpenAIEndpointError> {
        do {
            let config = try await service.save(draft)
            statusMessages[config.id] = "Saved. Saving does not connect — use Refresh Models or Test."
            await reload()
            return .success(config)
        } catch let error as OpenAIEndpointError {
            return .failure(error)
        } catch {
            return .failure(.invalidURL(error.localizedDescription))
        }
    }

    func remove(_ id: String) async {
        try? await service.remove(id)
        statusMessages[id] = nil
        await reload()
    }

    func refreshModels(_ id: String) async {
        await perform(id) { service in
            let models = try await service.discoverModels(id)
            return models.isEmpty ? "The server returned no models." : "Found \(models.count) model\(models.count == 1 ? "" : "s")."
        }
    }

    /// Discovery, a tiny generation and a tool-calling probe — the same as
    /// `ai-endpoint-test` with `tools: true`.
    func test(_ id: String) async {
        await perform(id) { service in
            let outcome = try await service.test(id, model: nil, generate: true, tools: true)
            return Self.summary(of: outcome)
        }
    }

    /// Makes the endpoint the active AI backend after a live check.
    func use(_ id: String) async {
        await perform(id) { service in
            let health = try await service.select(id, model: nil)
            guard let active = await service.activeEndpoint() else { throw OpenAIEndpointError.endpointNotFound }
            await MainActor.run {
                AIState.shared.activateOpenAI(model: active.model, capabilities: active.config.capabilities.legacyList)
            }
            return "In use with \(active.model). Health: \(OpenAIHealthLabel.text(for: health.state))."
        }
    }

    private func perform(_ id: String, _ action: @escaping (OpenAIEndpointService) async throws -> String) async {
        busyIds.insert(id)
        statusMessages[id] = nil
        defer { busyIds.remove(id) }
        do {
            statusMessages[id] = try await action(service)
        } catch let error as OpenAIEndpointError {
            statusMessages[id] = error.message
        } catch {
            statusMessages[id] = error.localizedDescription
        }
        await reload()
    }

    private static func summary(of outcome: OpenAIEndpointService.TestOutcome) -> String {
        var parts = ["Health: \(OpenAIHealthLabel.text(for: outcome.health.state))."]
        if let error = outcome.discoveryError { parts.append("Discovery: \(error.message)") }
        if let generation = outcome.generation {
            parts.append(generation.ok
                ? "Generation OK (\(generation.latencyMs) ms)."
                : "Generation failed: \(generation.error?.message ?? "no output").")
        }
        if let tools = outcome.toolCalling {
            parts.append("Tool calling \(tools.ok ? "OK" : "failed"): \(tools.detail)")
        }
        return parts.joined(separator: " ")
    }
}

/// Human-readable health labels shared by the list and the editor.
enum OpenAIHealthLabel {
    static func text(for state: OpenAIEndpointHealth.State) -> String {
        switch state {
        case .unknown: return "unknown"
        case .unreachable: return "unreachable"
        case .authFailed: return "auth failed"
        case .loading: return "loading"
        case .noModel: return "no model"
        case .modelMissing: return "model missing"
        case .ready: return "ready"
        case .busy: return "busy"
        }
    }
}
