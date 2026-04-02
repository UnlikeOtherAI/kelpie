import Combine
import Foundation

@MainActor
final class AIState: ObservableObject {
    static let shared = AIState()

    private enum DefaultsKey {
        static let backend = "ai.backend"
        static let activeModel = "ai.activeModel"
        static let ollamaEndpoint = "ai.ollamaEndpoint"
    }

    nonisolated static let defaultOllamaEndpoint = "http://localhost:11434"

    let isAvailable: Bool

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
        if #available(iOS 26, *) {
            isAvailable = true
        } else {
            isAvailable = false
        }

        let defaults = UserDefaults.standard
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
}
