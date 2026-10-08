import Foundation

/// Capability values a person declared for an endpoint. `nil` = not declared.
struct OpenAIDeclaredCapabilities: Codable, Equatable, Sendable {
    var contextWindow: Int?
    var vision: Bool?
    var toolCalling: Bool?
    var jsonSchema: Bool?
}

/// A model as last discovered from the server.
struct OpenAIStoredModel: Codable, Equatable, Sendable {
    let id: String
    let contextWindow: Int?
    let vision: Bool?
    let status: String?

    init(_ info: OpenAIModelInfo) {
        id = info.id
        contextWindow = info.contextWindow
        vision = info.vision
        status = info.status?.rawValue
    }

    var info: OpenAIModelInfo {
        OpenAIModelInfo(id: id, contextWindow: contextWindow, vision: vision, status: status.flatMap(OpenAIModelInfo.Status.init))
    }
}

/// A saved, user-named endpoint. The API key is not part of this value — it
/// lives in `SecretStore` under `apiKeyName`.
struct OpenAIEndpointConfig: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    /// Normalised base URL string (see `OpenAIEndpointURL`).
    var baseURL: String
    var model: String?
    var declared = OpenAIDeclaredCapabilities()
    /// Result of the last bounded tool-calling probe and the model it ran on.
    var testedToolCalling: Bool?
    var testedToolCallingModel: String?
    var models: [OpenAIStoredModel] = []
    var modelsDiscoveredAt: Date?

    var apiKeyName: String { "openai-endpoint.\(id).apiKey" }

    var url: OpenAIEndpointURL? { try? OpenAIEndpointURL.normalize(baseURL) }

    var selectedModelInfo: OpenAIModelInfo? {
        guard let model else { return nil }
        return models.first { $0.id == model }?.info
    }

    var capabilities: OpenAIEffectiveCapabilities {
        let server = selectedModelInfo
        let tested = (testedToolCallingModel == model) ? testedToolCalling : nil
        return OpenAIEffectiveCapabilities(
            contextWindow: .pick(user: declared.contextWindow, server: server?.contextWindow, test: nil),
            vision: .pick(user: declared.vision, server: server?.vision, test: nil),
            toolCalling: .pick(user: declared.toolCalling, server: nil, test: tested),
            jsonSchema: .pick(user: declared.jsonSchema, server: nil, test: nil)
        )
    }
}

/// A capability value with its provenance.
struct OpenAICapability<Value: Equatable & Sendable>: Equatable, Sendable {
    enum Source: String, Sendable {
        case user
        case server
        case test
    }

    let value: Value?
    let source: Source?

    static func pick(user: Value?, server: Value?, test: Value?) -> Self {
        if let user { return Self(value: user, source: .user) }
        if let test { return Self(value: test, source: .test) }
        if let server { return Self(value: server, source: .server) }
        return Self(value: nil, source: nil)
    }

    var json: [String: Any] {
        ["value": value.map { $0 as Any } ?? NSNull(), "source": source?.rawValue ?? NSNull()]
    }
}

struct OpenAIEffectiveCapabilities: Equatable, Sendable {
    let contextWindow: OpenAICapability<Int>
    let vision: OpenAICapability<Bool>
    let toolCalling: OpenAICapability<Bool>
    let jsonSchema: OpenAICapability<Bool>

    var json: [String: Any] {
        [
            "contextWindow": contextWindow.json,
            "vision": vision.json,
            "toolCalling": toolCalling.json,
            "jsonSchema": jsonSchema.json
        ]
    }

    /// Flat list in the shape `ai-status` has always used.
    var legacyList: [String] {
        var list = ["text"]
        if vision.value == true { list.append("vision") }
        if toolCalling.value == true { list.append("tools") }
        return list
    }
}
