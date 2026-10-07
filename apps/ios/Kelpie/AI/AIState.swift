import Combine
import Foundation

@MainActor
final class AIState: ObservableObject {
    static let shared = AIState()

    private enum DefaultsKey {
        static let backend = "ai.backend"
        static let activeModel = "ai.activeModel"
        static let ollamaEndpoint = "ai.ollamaEndpoint"
        /// Legacy plaintext key — migrated into SecretStore on first launch then removed.
        static let legacyHuggingFaceToken = "huggingFaceToken"
    }

    private enum SecretKey {
        static let huggingFaceToken = "huggingFaceToken"
    }

    nonisolated static let defaultOllamaEndpoint = "http://localhost:11434"

    let isAvailable: Bool

    @Published var huggingFaceToken: String {
        didSet {
            if huggingFaceToken.isEmpty {
                SecretStore.shared.remove(SecretKey.huggingFaceToken)
            } else {
                SecretStore.shared.set(SecretKey.huggingFaceToken, value: huggingFaceToken)
            }
        }
    }

    @Published var backend: String {
        didSet {
            UserDefaults.standard.set(backend, forKey: DefaultsKey.backend)
        }
    }

    @Published var activeModel: String? {
        didSet {
            if let activeModel {
                UserDefaults.standard.set(activeModel, forKey: DefaultsKey.activeModel)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.activeModel)
            }
        }
    }

    var ollamaEndpoint: String {
        get {
            let stored = UserDefaults.standard.string(forKey: DefaultsKey.ollamaEndpoint)
            return stored?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                // swiftlint:disable:next force_unwrapping
                ? stored!
                : Self.defaultOllamaEndpoint
        }
        set {
            let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(
                normalized.isEmpty ? Self.defaultOllamaEndpoint : normalized,
                forKey: DefaultsKey.ollamaEndpoint
            )
        }
    }

    /// Capabilities of the selected OpenAI-compatible endpoint model, mirrored
    /// from `OpenAIEndpointService` (the authority for that selection).
    @Published private(set) var openAICapabilities: [String] = []

    /// Bumped on every explicit backend change so an in-flight endpoint
    /// sync cannot overwrite a newer choice with a stale read.
    private var selectionGeneration = 0
    private var cancellables = Set<AnyCancellable>()

    var isLoaded: Bool {
        switch backend {
        case "ollama", "openai":
            return activeModel != nil
        case "platform":
            return isAvailable
        default:
            return false
        }
    }

    var capabilities: [String] {
        switch backend {
        case "ollama":
            return activeModel == nil ? [] : ["text"]
        case "openai":
            return activeModel == nil ? [] : openAICapabilities
        case "platform":
            return isAvailable ? ["text"] : []
        default:
            return []
        }
    }

    private init() {
        isAvailable = PlatformAIEngine.isAvailable

        let defaults = UserDefaults.standard
        huggingFaceToken = Self.loadHuggingFaceTokenWithMigration(defaults: defaults)
        let storedModel = defaults.string(forKey: DefaultsKey.activeModel)
        let storedBackend = defaults.string(forKey: DefaultsKey.backend) ?? "platform"

        let openAISelection = Self.persistedOpenAISelection()
        if storedBackend == "ollama", let storedModel, !storedModel.isEmpty {
            backend = "ollama"
            activeModel = storedModel
        } else if storedBackend == "openai", let openAISelection {
            backend = "openai"
            activeModel = openAISelection.model
        } else {
            backend = "platform"
            activeModel = nil
            defaults.set("platform", forKey: DefaultsKey.backend)
            defaults.removeObject(forKey: DefaultsKey.activeModel)
        }

        if defaults.string(forKey: DefaultsKey.ollamaEndpoint) == nil {
            defaults.set(Self.defaultOllamaEndpoint, forKey: DefaultsKey.ollamaEndpoint)
        }

        if backend != "openai", openAISelection != nil {
            // Another backend was chosen last; an endpoint selection left
            // behind must not keep polling or answer `ai-status`.
            Task { await OpenAIEndpointService.shared.clearActive() }
        }
        NotificationCenter.default.publisher(for: .openAIEndpointsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncOpenAISelection() }
            .store(in: &cancellables)
        syncOpenAISelection()
    }

    func activatePlatform() {
        selectionGeneration += 1
        backend = "platform"
        activeModel = nil
        openAICapabilities = []
    }

    func activateOllama(model: String, endpoint: String) {
        selectionGeneration += 1
        backend = "ollama"
        activeModel = model
        ollamaEndpoint = endpoint
        openAICapabilities = []
    }

    /// Called after `OpenAIEndpointService.select` succeeded.
    func activateOpenAI(model: String, capabilities: [String]) {
        selectionGeneration += 1
        backend = "openai"
        activeModel = model
        openAICapabilities = capabilities
    }

    /// Mirrors the endpoint service while openai is the backend: model and
    /// capability changes are copied, and a cleared selection (endpoint
    /// removed, address changed, unloaded over the API) shows platform again.
    /// That is display state only — inference never falls back on its own.
    func syncOpenAISelection() {
        guard backend == "openai" else { return }
        let generation = selectionGeneration
        Task { @MainActor [weak self] in
            let active = await OpenAIEndpointService.shared.activeEndpoint()
            guard let self, generation == self.selectionGeneration, self.backend == "openai" else { return }
            if let active {
                self.activeModel = active.model
                self.openAICapabilities = active.config.capabilities.legacyList
            } else {
                self.activatePlatform()
            }
        }
    }

    /// The persisted endpoint selection, if it still names a saved endpoint.
    private static func persistedOpenAISelection() -> OpenAIActiveSelection? {
        let persistence = OpenAIEndpointPersistence(defaults: .standard)
        guard let active = persistence.loadActive(),
              persistence.loadEndpoints().contains(where: { $0.id == active.endpointId }) else { return nil }
        return active
    }

    /// Migrates any plaintext HF token previously stored in `UserDefaults`
    /// into `SecretStore` and deletes the plaintext copy.
    private static func loadHuggingFaceTokenWithMigration(defaults: UserDefaults) -> String {
        let store = SecretStore.shared
        if let legacy = defaults.string(forKey: DefaultsKey.legacyHuggingFaceToken) {
            defaults.removeObject(forKey: DefaultsKey.legacyHuggingFaceToken)
            if !legacy.isEmpty {
                if store.get(SecretKey.huggingFaceToken) == nil {
                    store.set(SecretKey.huggingFaceToken, value: legacy)
                }
                return legacy
            }
        }
        return store.get(SecretKey.huggingFaceToken) ?? ""
    }
}
