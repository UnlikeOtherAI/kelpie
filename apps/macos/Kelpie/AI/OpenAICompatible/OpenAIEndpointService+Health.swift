import Foundation

// MARK: - Discovery, health, tests and polling

extension OpenAIEndpointService {
    struct TestOutcome: Sendable {
        let health: OpenAIEndpointHealth
        let models: [OpenAIModelInfo]?
        let discoveryError: OpenAIEndpointError?
        let generation: (ok: Bool, latencyMs: Int, text: String, error: OpenAIEndpointError?)?
        let toolCalling: (ok: Bool, detail: String)?
    }

    /// `GET /models`, storing the list on success.
    func discoverModels(_ idOrName: String) async throws -> [OpenAIModelInfo] {
        let config = try resolve(idOrName)
        let models = try await client(for: config).listModels()
        record(models: models, for: config.id)
        return models
    }

    /// Probes discovery and recomputes health for one endpoint.
    @discardableResult
    func refreshHealth(_ idOrName: String) async throws -> OpenAIEndpointHealth {
        let config = try resolve(idOrName)
        let started = now()
        let discovery: Result<[OpenAIModelInfo], OpenAIEndpointError>
        do {
            let models = try await client(for: config).listModels()
            record(models: models, for: config.id)
            discovery = .success(models)
        } catch let error as OpenAIEndpointError {
            discovery = .failure(error)
        } catch {
            discovery = .failure(.unreachable(error.localizedDescription))
        }
        let finished = now()
        let latency = Int(finished.timeIntervalSince(started) * 1_000)
        let model = (active?.endpointId == config.id ? active?.model : nil) ?? config.model
        let next = OpenAIHealthEvaluator.evaluate(
            discovery: discovery,
            selectedModel: model,
            previous: health[config.id] ?? OpenAIEndpointHealth(),
            now: finished,
            latencyMs: latency
        )
        health[config.id] = next
        consecutiveFailures[config.id] = next.state.isOnline ? 0 : (consecutiveFailures[config.id] ?? 0) + 1
        notifyChanged()
        return next
    }

    /// Bounded readiness test: discovery, a tiny generation and an optional
    /// tool-calling probe. A passing tool probe records `toolCalling` with
    /// source `test` for the tested model.
    func test(_ idOrName: String, model requestedModel: String?, generate: Bool, tools: Bool) async throws -> TestOutcome {
        var config = try resolve(idOrName)
        if let requestedModel, !requestedModel.isEmpty, requestedModel != config.model {
            config.model = requestedModel
            health[config.id] = nil
            store(config)
        }
        var discoveryError: OpenAIEndpointError?
        var models: [OpenAIModelInfo]?
        do {
            models = try await discoverModels(config.id)
        } catch let error as OpenAIEndpointError {
            discoveryError = error
        }
        var current = try await refreshHealth(config.id)
        guard current.state.isOnline, let model = config.model else {
            return TestOutcome(health: current, models: models, discoveryError: discoveryError, generation: nil, toolCalling: nil)
        }

        let client = try client(for: config)
        var generation: (ok: Bool, latencyMs: Int, text: String, error: OpenAIEndpointError?)?
        if generate {
            generation = await runGenerationProbe(client: client, model: model, endpointId: config.id)
            if generation?.ok == true {
                current.generationVerifiedAt = now()
                if current.state == .modelMissing, current.modelListed == nil {
                    current.state = .ready
                    current.message = "Model discovery is unsupported; a generation test passed."
                }
                health[config.id] = current
            }
        }
        var toolResult: (ok: Bool, detail: String)?
        if tools {
            toolResult = await runToolProbe(client: client, model: model, endpointId: config.id)
            if var updated = endpoints.first(where: { $0.id == config.id }) {
                updated.testedToolCalling = toolResult?.ok
                updated.testedToolCallingModel = model
                store(updated)
            }
        }
        notifyChanged()
        return TestOutcome(
            health: health[config.id] ?? current,
            models: models,
            discoveryError: discoveryError,
            generation: generation,
            toolCalling: toolResult
        )
    }

    private func runGenerationProbe(
        client: OpenAIEndpointClient,
        model: String,
        endpointId: String
    ) async -> (ok: Bool, latencyMs: Int, text: String, error: OpenAIEndpointError?) {
        let started = now()
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "Reply with the single word OK."]],
            "max_tokens": 256,
            "temperature": 0
        ]
        do {
            let result = try await run(on: endpointId) { try await client.chat(body: body, timeout: 120) }
            let latency = Int(now().timeIntervalSince(started) * 1_000)
            let text = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
            // Reasoning models may spend the budget thinking; any output proves generation.
            let produced = !text.isEmpty || !result.reasoning.isEmpty
            return (produced, latency, String(text.prefix(200)), produced ? nil : .malformedResponse("empty completion"))
        } catch {
            let mapped = (error as? OpenAIEndpointError) ?? .unreachable(error.localizedDescription)
            return (false, Int(now().timeIntervalSince(started) * 1_000), "", mapped)
        }
    }

    private func runToolProbe(client: OpenAIEndpointClient, model: String, endpointId: String) async -> (ok: Bool, detail: String) {
        let body: [String: Any] = [
            "model": model,
            "messages": [[
                "role": "user",
                "content": "Use the get_time tool with timezone \"UTC\". Do not answer in text."
            ]],
            "tools": [[
                "type": "function",
                "function": [
                    "name": "get_time",
                    "description": "Returns the current time in a timezone.",
                    "parameters": [
                        "type": "object",
                        "properties": ["timezone": ["type": "string"]],
                        "required": ["timezone"]
                    ]
                ]
            ]],
            "max_tokens": 512,
            "temperature": 0
        ]
        do {
            let result = try await run(on: endpointId) { try await client.chat(body: body, timeout: 120) }
            guard let call = result.toolCalls.first else {
                return (false, "The model answered without calling the tool.")
            }
            guard call.name == "get_time", let args = call.parsedArguments else {
                return (false, "The model produced an invalid tool call (\(call.name)).")
            }
            return (true, "Called get_time with \(args["timezone"] as? String ?? "?").")
        } catch {
            let mapped = (error as? OpenAIEndpointError) ?? .unreachable(error.localizedDescription)
            return (false, mapped.message)
        }
    }

    private func record(models: [OpenAIModelInfo], for id: String) {
        guard var config = endpoints.first(where: { $0.id == id }) else { return }
        config.models = models.map(OpenAIStoredModel.init)
        config.modelsDiscoveredAt = now()
        store(config)
    }

    // MARK: - Public JSON

    func publicJSON(_ config: OpenAIEndpointConfig) -> [String: Any] {
        let url = config.url
        return [
            "id": config.id,
            "name": config.name,
            "baseURL": config.baseURL,
            "loopback": url?.isLoopback ?? false,
            "hasApiKey": hasApiKey(config),
            "model": config.model ?? NSNull(),
            "capabilities": config.capabilities.json,
            "models": config.models.map { $0.info.publicJSON },
            "modelsDiscoveredAt": config.modelsDiscoveredAt.map(OpenAIEndpointHealth.iso) ?? NSNull(),
            "active": active?.endpointId == config.id,
            "health": healthJSON(config.id)
        ]
    }

    func healthJSON(_ id: String) -> [String: Any] {
        (health[id] ?? OpenAIEndpointHealth()).publicJSON(now: now(), inFlight: inFlight[id] ?? 0)
    }

    func listJSON() -> [String: Any] {
        [
            "endpoints": endpoints.map(publicJSON),
            "activeEndpointId": active?.endpointId ?? NSNull(),
            "activeModel": active?.model ?? NSNull()
        ]
    }

    // MARK: - Polling

    /// Re-check the active endpoint now (wake, network change, panel opened).
    func refreshActiveNow() {
        restartPolling()
    }

    func restartPolling() {
        pollTask?.cancel()
        guard let endpointId = active?.endpointId else {
            pollTask = nil
            return
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let state = (try? await self.refreshHealth(endpointId))?.state ?? .unknown
                let failures = await self.consecutiveFailures[endpointId] ?? 0
                let delay = OpenAIHealthEvaluator.nextPollDelay(for: state, consecutiveFailures: failures)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
}
