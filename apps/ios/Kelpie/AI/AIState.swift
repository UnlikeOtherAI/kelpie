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

    var isLoaded: Bool {
        switch backend {
        case "ollama":
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

        if storedBackend == "ollama", let storedModel, !storedModel.isEmpty {
            backend = "ollama"
            activeModel = storedModel
        } else {
            backend = "platform"
            activeModel = nil
            defaults.set("platform", forKey: DefaultsKey.backend)
            defaults.removeObject(forKey: DefaultsKey.activeModel)
        }

        if defaults.string(forKey: DefaultsKey.ollamaEndpoint) == nil {
            defaults.set(Self.defaultOllamaEndpoint, forKey: DefaultsKey.ollamaEndpoint)
        }
    }

    func activatePlatform() {
        backend = "platform"
        activeModel = nil
    }

    func activateOllama(model: String, endpoint: String) {
        backend = "ollama"
        activeModel = model
        ollamaEndpoint = endpoint
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
