import Foundation

/// Secret storage seam (API keys). Production uses Kelpie's encrypted
/// `SecretStore`; tests use an in-memory fake.
protocol OpenAISecretStoring: AnyObject, Sendable {
    func get(_ name: String) -> String?
    func set(_ name: String, value: String)
    func remove(_ name: String)
}

extension SecretStore: OpenAISecretStoring, @unchecked Sendable {}

/// The endpoint + model that is currently Kelpie's active AI backend.
struct OpenAIActiveSelection: Codable, Equatable, Sendable {
    let endpointId: String
    let model: String
}

/// Non-secret endpoint configuration in UserDefaults.
struct OpenAIEndpointPersistence: @unchecked Sendable {
    static let endpointsKey = "ai.openaiEndpoints.v1"
    static let activeKey = "ai.openaiActive.v1"

    let defaults: UserDefaults

    func loadEndpoints() -> [OpenAIEndpointConfig] {
        guard let data = defaults.data(forKey: Self.endpointsKey) else { return [] }
        return (try? JSONDecoder().decode([OpenAIEndpointConfig].self, from: data)) ?? []
    }

    func saveEndpoints(_ endpoints: [OpenAIEndpointConfig]) {
        guard let data = try? JSONEncoder().encode(endpoints) else { return }
        defaults.set(data, forKey: Self.endpointsKey)
    }

    func loadActive() -> OpenAIActiveSelection? {
        guard let data = defaults.data(forKey: Self.activeKey) else { return nil }
        return try? JSONDecoder().decode(OpenAIActiveSelection.self, from: data)
    }

    func saveActive(_ active: OpenAIActiveSelection?) {
        guard let active, let data = try? JSONEncoder().encode(active) else {
            defaults.removeObject(forKey: Self.activeKey)
            return
        }
        defaults.set(data, forKey: Self.activeKey)
    }
}

extension Notification.Name {
    /// Posted on the main queue whenever endpoints, selection or health change.
    static let openAIEndpointsDidChange = Notification.Name("kelpie.openAIEndpointsDidChange")
}
