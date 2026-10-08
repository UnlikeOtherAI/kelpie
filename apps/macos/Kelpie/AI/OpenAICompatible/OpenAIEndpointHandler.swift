import Foundation

/// Device HTTP methods for managing OpenAI-compatible endpoints. Shared by
/// macOS and iOS; platform behaviour is injected through `Host`.
struct OpenAIEndpointHandler {
    struct Host: Sendable {
        /// "macos" / "ios".
        let platform: String
        /// Plain-language explanation of what loopback addresses mean here.
        let loopbackMeans: String
    }

    let service: OpenAIEndpointService
    let host: Host

    func register(on router: Router) {
        router.register("ai-endpoints") { _ in await list() }
        router.register("ai-endpoint-save") { body in await save(body) }
        router.register("ai-endpoint-remove") { body in await remove(body) }
        router.register("ai-endpoint-models") { body in await models(body) }
        router.register("ai-endpoint-test") { body in await test(body) }
        router.register("ai-endpoint-health") { body in await health(body) }
        router.register("ai-cancel") { _ in await cancel() }
    }

    var executionHostJSON: [String: Any] {
        ["platform": host.platform, "loopbackMeans": host.loopbackMeans]
    }

    private func list() async -> [String: Any] {
        var payload = await service.listJSON()
        payload["executionHost"] = executionHostJSON
        return successResponse(payload)
    }

    private func save(_ body: [String: Any]) async -> [String: Any] {
        let id = Self.string(body["id"])
        let existing = await id.asyncFlatMap { try? await service.resolve($0) }
        if id != nil && existing == nil { return OpenAIEndpointError.endpointNotFound.response }
        if body["apiKey"] != nil && !(body["apiKey"] is String) {
            return errorResponse(code: "INVALID_PARAM", message: "apiKey must be a string")
        }

        let model: String?
        if body.keys.contains("model") {
            model = Self.string(body["model"])
        } else {
            model = existing?.model
        }
        let declared = Self.mergeDeclared(existing?.declared ?? OpenAIDeclaredCapabilities(), patch: body["capabilities"])
        let draft = OpenAIEndpointService.Draft(
            id: id,
            name: Self.string(body["name"]) ?? existing?.name ?? "",
            baseURL: Self.string(body["baseURL"]) ?? existing?.baseURL ?? "",
            apiKey: body["apiKey"] as? String,
            clearApiKey: body["clearApiKey"] as? Bool ?? false,
            model: model,
            declared: declared
        )
        do {
            let config = try await service.save(draft)
            return successResponse(["endpoint": await service.publicJSON(config)])
        } catch let error as OpenAIEndpointError {
            return error.response
        } catch {
            return errorResponse(code: "INVALID_PARAM", message: error.localizedDescription)
        }
    }

    private func remove(_ body: [String: Any]) async -> [String: Any] {
        guard let id = Self.string(body["id"]) else { return errorResponse(code: "MISSING_PARAM", message: "id is required") }
        do {
            try await service.remove(id)
            return successResponse(["removed": true])
        } catch let error as OpenAIEndpointError {
            return error.response
        } catch {
            return errorResponse(code: "INVALID_PARAM", message: error.localizedDescription)
        }
    }

    private func models(_ body: [String: Any]) async -> [String: Any] {
        guard let id = Self.string(body["id"]) else { return errorResponse(code: "MISSING_PARAM", message: "id is required") }
        do {
            let models = try await service.discoverModels(id)
            var payload: [String: Any] = ["models": models.map(\.publicJSON)]
            if models.isEmpty { payload["warning"] = "The server returned no models." }
            return successResponse(payload)
        } catch let error as OpenAIEndpointError {
            return error.response
        } catch {
            return OpenAIEndpointError.unreachable(error.localizedDescription).response
        }
    }

    private func test(_ body: [String: Any]) async -> [String: Any] {
        guard let id = Self.string(body["id"]) else { return errorResponse(code: "MISSING_PARAM", message: "id is required") }
        do {
            let outcome = try await service.test(
                id,
                model: Self.string(body["model"]),
                generate: body["generate"] as? Bool ?? true,
                tools: body["tools"] as? Bool ?? false
            )
            let config = try await service.resolve(id)
            var payload: [String: Any] = [
                "health": await service.healthJSON(config.id),
                "endpoint": await service.publicJSON(config)
            ]
            if let models = outcome.models { payload["models"] = models.map(\.publicJSON) }
            if let error = outcome.discoveryError {
                payload["discoveryError"] = ["code": error.code, "message": error.message]
            }
            if let generation = outcome.generation {
                var json: [String: Any] = ["ok": generation.ok, "latencyMs": generation.latencyMs, "text": generation.text]
                if let error = generation.error { json["error"] = ["code": error.code, "message": error.message] }
                payload["generation"] = json
            }
            if let tools = outcome.toolCalling {
                payload["toolCalling"] = ["ok": tools.ok, "detail": tools.detail]
            }
            return successResponse(payload)
        } catch let error as OpenAIEndpointError {
            return error.response
        } catch {
            return OpenAIEndpointError.unreachable(error.localizedDescription).response
        }
    }

    private func health(_ body: [String: Any]) async -> [String: Any] {
        let requested = Self.string(body["id"])
        let fallback = await service.activeEndpoint()?.config.id
        guard let id = requested ?? fallback else {
            return errorResponse(code: "NO_MODEL_SELECTED", message: "Pass an endpoint id or select an endpoint first.")
        }
        do {
            let config = try await service.resolve(id)
            if body["refresh"] as? Bool ?? false {
                try await service.refreshHealth(config.id)
            }
            return successResponse(["endpointId": config.id, "health": await service.healthJSON(config.id)])
        } catch let error as OpenAIEndpointError {
            return error.response
        } catch {
            return OpenAIEndpointError.unreachable(error.localizedDescription).response
        }
    }

    private func cancel() async -> [String: Any] {
        successResponse(["cancelled": await service.cancelAll()])
    }

    // MARK: - Parsing helpers

    static func string(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// Applies `{key: value | null}` to declared capabilities; absent keys are kept.
    static func mergeDeclared(_ base: OpenAIDeclaredCapabilities, patch: Any?) -> OpenAIDeclaredCapabilities {
        guard let patch = patch as? [String: Any] else { return base }
        var merged = base
        if patch.keys.contains("contextWindow") {
            merged.contextWindow = (patch["contextWindow"] as? NSNumber).map(\.intValue).flatMap { $0 > 0 ? $0 : nil }
        }
        if patch.keys.contains("vision") { merged.vision = patch["vision"] as? Bool }
        if patch.keys.contains("toolCalling") { merged.toolCalling = patch["toolCalling"] as? Bool }
        if patch.keys.contains("jsonSchema") { merged.jsonSchema = patch["jsonSchema"] as? Bool }
        return merged
    }
}

private extension Optional {
    func asyncFlatMap<U>(_ transform: (Wrapped) async -> U?) async -> U? {
        guard let value = self else { return nil }
        return await transform(value)
    }
}
