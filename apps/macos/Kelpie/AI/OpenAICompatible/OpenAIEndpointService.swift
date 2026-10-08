import Foundation

/// Owns saved OpenAI-compatible endpoints, the active selection, live health
/// and in-flight inference. Shared by macOS and iOS.
///
/// Health probing, testing and polling live in
/// `OpenAIEndpointService+Health.swift`.
actor OpenAIEndpointService {
    static let shared = OpenAIEndpointService(
        persistence: OpenAIEndpointPersistence(defaults: .standard),
        secrets: SecretStore.shared,
        transport: URLSessionOpenAITransport.shared
    )

    struct Draft: Sendable {
        var id: String?
        var name: String
        var baseURL: String
        /// New key; `nil` keeps the stored key.
        var apiKey: String?
        var clearApiKey = false
        var model: String?
        var declared: OpenAIDeclaredCapabilities
    }

    let persistence: OpenAIEndpointPersistence
    let secrets: OpenAISecretStoring
    let transport: OpenAIHTTPTransport
    var now: @Sendable () -> Date = { Date() }

    private(set) var endpoints: [OpenAIEndpointConfig]
    private(set) var active: OpenAIActiveSelection?
    var health: [String: OpenAIEndpointHealth] = [:]
    var consecutiveFailures: [String: Int] = [:]
    var inFlight: [String: Int] = [:]
    var runs: [UUID: Task<Void, Never>] = [:]
    var pollTask: Task<Void, Never>?

    init(persistence: OpenAIEndpointPersistence, secrets: OpenAISecretStoring, transport: OpenAIHTTPTransport) {
        self.persistence = persistence
        self.secrets = secrets
        self.transport = transport
        endpoints = persistence.loadEndpoints()
        let storedActive = persistence.loadActive()
        active = endpoints.contains { $0.id == storedActive?.endpointId } ? storedActive : nil
    }

    // MARK: - Lookup

    func resolve(_ idOrName: String) throws -> OpenAIEndpointConfig {
        let key = idOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = endpoints.first(where: { $0.id == key }) { return match }
        if let match = endpoints.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame }) { return match }
        throw OpenAIEndpointError.endpointNotFound
    }

    func client(for config: OpenAIEndpointConfig) throws -> OpenAIEndpointClient {
        guard let url = config.url else { throw OpenAIEndpointError.invalidURL("The saved base URL is invalid.") }
        return OpenAIEndpointClient(baseURL: url, apiKey: secrets.get(config.apiKeyName), transport: transport)
    }

    func activeEndpoint() -> (config: OpenAIEndpointConfig, model: String)? {
        guard let active, let config = endpoints.first(where: { $0.id == active.endpointId }) else { return nil }
        return (config, active.model)
    }

    func hasApiKey(_ config: OpenAIEndpointConfig) -> Bool {
        !(secrets.get(config.apiKeyName) ?? "").isEmpty
    }

    // MARK: - CRUD

    func save(_ draft: Draft) throws -> OpenAIEndpointConfig {
        let normalized: OpenAIEndpointURL
        do {
            normalized = try OpenAIEndpointURL.normalize(draft.baseURL)
        } catch let error as OpenAIEndpointURL.ValidationError {
            throw OpenAIEndpointError.invalidURL(error.message)
        }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw OpenAIEndpointError.invalidURL("Give the endpoint a name.") }
        if endpoints.contains(where: { $0.id != draft.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            throw OpenAIEndpointError.invalidURL("Another endpoint is already named \"\(name)\".")
        }

        var config: OpenAIEndpointConfig
        if let id = draft.id {
            guard let existing = endpoints.first(where: { $0.id == id }) else { throw OpenAIEndpointError.endpointNotFound }
            config = existing
        } else {
            config = OpenAIEndpointConfig(id: UUID().uuidString.lowercased(), name: name, baseURL: normalized.string)
        }
        let addressChanged = config.baseURL != normalized.string
        let model = draft.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelChanged = (model?.isEmpty == false ? model : nil) != config.model

        config.name = name
        config.baseURL = normalized.string
        config.model = model?.isEmpty == false ? model : nil
        config.declared = draft.declared
        if addressChanged {
            config.models = []
            config.modelsDiscoveredAt = nil
            config.testedToolCalling = nil
            config.testedToolCallingModel = nil
        }
        if addressChanged || modelChanged { health[config.id] = nil }

        if draft.clearApiKey {
            secrets.remove(config.apiKeyName)
            health[config.id] = nil
        } else if let key = draft.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            secrets.set(config.apiKeyName, value: key)
            health[config.id] = nil
        }

        store(config)
        if let active, active.endpointId == config.id {
            if addressChanged || config.model == nil {
                // The selection no longer describes what the person chose.
                setActive(nil)
            } else if let model = config.model, model != active.model {
                setActive(OpenAIActiveSelection(endpointId: config.id, model: model))
            }
        }
        notifyChanged()
        return config
    }

    func remove(_ idOrName: String) throws {
        let config = try resolve(idOrName)
        endpoints.removeAll { $0.id == config.id }
        persistence.saveEndpoints(endpoints)
        secrets.remove(config.apiKeyName)
        health[config.id] = nil
        if active?.endpointId == config.id { setActive(nil) }
        notifyChanged()
    }

    func store(_ config: OpenAIEndpointConfig) {
        if let index = endpoints.firstIndex(where: { $0.id == config.id }) {
            endpoints[index] = config
        } else {
            endpoints.append(config)
        }
        persistence.saveEndpoints(endpoints)
    }

    // MARK: - Selection

    /// Makes `endpoint` + `model` the active backend after a live probe.
    /// Unreachable or unauthorised endpoints are refused and the current
    /// selection is left untouched.
    func select(_ idOrName: String, model requestedModel: String?) async throws -> OpenAIEndpointHealth {
        var config = try resolve(idOrName)
        let model = (requestedModel?.isEmpty == false ? requestedModel : nil) ?? config.model
        guard let model else { throw OpenAIEndpointError.noModelSelected }
        if config.model != model {
            config.model = model
            health[config.id] = nil
            store(config)
        }
        let result = try await refreshHealth(config.id)
        switch result.state {
        case .unreachable:
            throw OpenAIEndpointError.unreachable(result.message)
        case .authFailed:
            throw OpenAIEndpointError.authFailed
        default:
            setActive(OpenAIActiveSelection(endpointId: config.id, model: model))
            notifyChanged()
            return result
        }
    }

    func clearActive() {
        guard active != nil else { return }
        setActive(nil)
        notifyChanged()
    }

    private func setActive(_ selection: OpenAIActiveSelection?) {
        active = selection
        persistence.saveActive(selection)
        restartPolling()
    }

    // MARK: - In-flight work and cancellation

    /// Runs `operation` as a cancellable, tracked inference on `endpointId`.
    func run<T: Sendable>(
        on endpointId: String,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let id = UUID()
        let box = ResultBox<T>()
        let task = Task<Void, Never> {
            do { box.result = .success(try await operation()) } catch { box.result = .failure(error) }
        }
        runs[id] = task
        inFlight[endpointId, default: 0] += 1
        notifyChanged()
        await task.value
        runs[id] = nil
        inFlight[endpointId, default: 1] -= 1
        notifyChanged()
        switch box.result {
        case .success(let value): return value
        case .failure(let error): throw UnifiedError.map(error, cancelled: task.isCancelled)
        case nil: throw OpenAIEndpointError.cancelled
        }
    }

    func cancelAll() -> Int {
        let count = runs.count
        runs.values.forEach { $0.cancel() }
        return count
    }

    func notifyChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .openAIEndpointsDidChange, object: nil)
        }
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

private enum UnifiedError {
    static func map(_ error: Error, cancelled: Bool) -> Error {
        if let failure = error as? OpenAIAgentLoop.Failure {
            return cancelled ? OpenAIAgentLoop.Failure(error: .cancelled, steps: failure.steps, reasoning: failure.reasoning) : failure
        }
        if cancelled || error is CancellationError { return OpenAIEndpointError.cancelled }
        if let urlError = error as? URLError, urlError.code == .cancelled { return OpenAIEndpointError.cancelled }
        return error
    }
}
