import AVFoundation
import Foundation

struct AIHandler {
    let context: HandlerContext

    private let platformEngine = PlatformAIEngine()
    private static let ollamaPrefix = "ollama:"
    private static let recorder = StubAudioRecorder()

    func register(on router: Router) {
        router.register("ai-status") { _ in await status() }
        router.register("ai-load") { body in await load(body) }
        router.register("ai-unload") { _ in await unload() }
        router.register("ai-infer") { body in await infer(body) }
        router.register("ai-record") { body in await record(body) }
    }

    private func status() async -> [String: Any] {
        await MainActor.run {
            let state = AIState.shared
            var response = successResponse([
                "loaded": state.isLoaded,
                "backend": state.backend,
                "capabilities": state.capabilities,
            ])

            if state.backend == "ollama", let model = state.activeModel {
                response["model"] = model
                response["ollamaEndpoint"] = state.ollamaEndpoint
            }

            return response
        }
    }

    private func load(_ body: [String: Any]) async -> [String: Any] {
        let start = CFAbsoluteTimeGetCurrent()
        let model = (body["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let model, model.hasPrefix(Self.ollamaPrefix) {
            let ollamaModel = String(model.dropFirst(Self.ollamaPrefix.count))
            guard !ollamaModel.isEmpty else {
                return errorResponse(code: "INVALID_PARAM", message: "Ollama model id cannot be empty")
            }

            let endpoint = normalizedOllamaEndpoint(body["ollamaEndpoint"] as? String)
            guard URL(string: endpoint) != nil else {
                return errorResponse(code: "INVALID_PARAM", message: "ollamaEndpoint must be a valid URL")
            }

            do {
                try await validateOllamaModel(model: ollamaModel, endpoint: endpoint)
                await MainActor.run {
                    AIState.shared.activateOllama(model: ollamaModel, endpoint: endpoint)
                }
                return successResponse([
                    "model": ollamaModel,
                    "backend": "ollama",
                    "ollamaEndpoint": endpoint,
                    "loadTimeMs": elapsedMs(since: start),
                ])
            } catch let error as AIHandlerError {
                return error.response
            } catch {
                return errorResponse(code: "OLLAMA_NOT_AVAILABLE", message: "Failed to reach Ollama at \(endpoint)")
            }
        }

        if body["path"] != nil {
            return errorResponse(
                code: "PLATFORM_NOT_SUPPORTED",
                message: "iOS does not support loading GGUF files directly"
            )
        }

        if let model, !model.isEmpty, model != "platform" {
            return errorResponse(
                code: "PLATFORM_NOT_SUPPORTED",
                message: "iOS only supports the platform backend or ollama: prefixed models"
            )
        }

        let payload = await MainActor.run { () -> [String: Any] in
            let state = AIState.shared
            state.activatePlatform()
            return [
                "loaded": state.isLoaded,
                "backend": state.backend,
                "capabilities": state.capabilities,
                "loadTimeMs": elapsedMs(since: start),
            ]
        }
        return successResponse(payload)
    }

    private func unload() async -> [String: Any] {
        await MainActor.run {
            AIState.shared.activatePlatform()
            return successResponse()
        }
    }

    private func infer(_ body: [String: Any]) async -> [String: Any] {
        let stateSnapshot = await MainActor.run { () -> (backend: String, model: String?, endpoint: String, available: Bool) in
            let state = AIState.shared
            return (state.backend, state.activeModel, state.ollamaEndpoint, state.isAvailable)
        }

        switch stateSnapshot.backend {
        case "ollama":
            guard let model = stateSnapshot.model, !model.isEmpty else {
                return errorResponse(code: "NO_MODEL_LOADED", message: "Load a model first with ai-load")
            }
            return await inferWithOllama(body, model: model, endpoint: stateSnapshot.endpoint)
        case "platform":
            guard stateSnapshot.available else {
                return errorResponse(code: "PLATFORM_AI_UNAVAILABLE", message: "Platform AI is unavailable on this device")
            }
            return await inferWithPlatform(body)
        default:
            return errorResponse(code: "INVALID_STATE", message: "Unknown AI backend: \(stateSnapshot.backend)")
        }
    }

    private func inferWithPlatform(_ body: [String: Any]) async -> [String: Any] {
        if body["audio"] != nil {
            return errorResponse(
                code: "AUDIO_NOT_SUPPORTED",
                message: "Platform AI currently supports text-only inference on iOS"
            )
        }

        if body["image"] != nil || body["images"] != nil || (body["context"] as? String) == "screenshot" {
            return errorResponse(
                code: "VISION_NOT_SUPPORTED",
                message: "Platform AI currently supports text-only inference on iOS"
            )
        }

        if body["messages"] != nil {
            return errorResponse(
                code: "INVALID_PARAM",
                message: "messages is only supported when the Ollama backend is active"
            )
        }

        let prompt = composePrompt(from: body)
        guard !prompt.isEmpty else {
            return errorResponse(code: "MISSING_PARAM", message: "prompt is required")
        }

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let response = try await platformEngine.infer(prompt: prompt)
            return successResponse([
                "response": response,
                "tokensUsed": 0,
                "inferenceTimeMs": elapsedMs(since: start),
            ])
        } catch {
            return errorResponse(
                code: "PLATFORM_AI_UNAVAILABLE",
                message: error.localizedDescription.isEmpty ? "Platform AI is not yet wired on iOS" : error.localizedDescription
            )
        }
    }

    private func inferWithOllama(_ body: [String: Any], model: String, endpoint: String) async -> [String: Any] {
        if body["audio"] != nil {
            return errorResponse(
                code: "AUDIO_NOT_SUPPORTED",
                message: "Remote Ollama inference does not accept raw audio in the iOS bridge"
            )
        }

        let start = CFAbsoluteTimeGetCurrent()

        do {
            if let messages = body["messages"] as? [[String: Any]] {
                let payload = try buildOllamaChatPayload(body: body, messages: messages, model: model)
                let result = try await postOllama(path: "/api/chat", payload: payload, endpoint: endpoint)
                let message = result["message"] as? [String: Any]
                let content = message?["content"] as? String ?? ""

                return successResponse([
                    "response": content,
                    "tokensUsed": result["eval_count"] as? Int ?? 0,
                    "inferenceTimeMs": elapsedMs(since: start),
                ])
            }

            let payload = try buildOllamaGeneratePayload(body: body, model: model)
            let result = try await postOllama(path: "/api/generate", payload: payload, endpoint: endpoint)
            let response = result["response"] as? String ?? ""

            return successResponse([
                "response": response,
                "tokensUsed": result["eval_count"] as? Int ?? 0,
                "inferenceTimeMs": elapsedMs(since: start),
            ])
        } catch let error as AIHandlerError {
            return error.response
        } catch {
            return errorResponse(code: "OLLAMA_DISCONNECTED", message: "Lost connection to Ollama during inference")
        }
    }

    private func record(_ body: [String: Any]) async -> [String: Any] {
        let action = (body["action"] as? String ?? "status").lowercased()

        do {
            switch action {
            case "start":
                try Self.recorder.start()
                return successResponse(["recording": true, "elapsedMs": 0])
            case "stop":
                let result = try Self.recorder.stop()
                return successResponse([
                    "recording": false,
                    "audio": result.audio.base64EncodedString(),
                    "durationMs": result.durationMs,
                ])
            case "status":
                let snapshot: [String: Any] = [
                    "recording": Self.recorder.isRecording,
                    "elapsedMs": Self.recorder.elapsedMs,
                ]
                return successResponse(snapshot)
            default:
                return errorResponse(code: "INVALID_PARAM", message: "action must be start, stop, or status")
            }
        } catch let error as RecorderError {
            return error.response
        } catch {
            return errorResponse(code: "RECORDING_FAILED", message: "Audio recording is unavailable")
        }
    }

    private func validateOllamaModel(model: String, endpoint: String) async throws {
        let result = try await postOllama(path: "/api/tags", payload: nil, endpoint: endpoint, method: "GET")
        let models = result["models"] as? [[String: Any]] ?? []
        let names = Set(models.compactMap { $0["name"] as? String })

        guard names.contains(model) else {
            throw AIHandlerError(
                code: "OLLAMA_MODEL_NOT_FOUND",
                message: "Ollama model '\(model)' is not installed at \(endpoint)"
            )
        }
    }

    private func buildOllamaGeneratePayload(body: [String: Any], model: String) throws -> [String: Any] {
        let prompt = composePrompt(from: body)
        guard !prompt.isEmpty else {
            throw AIHandlerError(code: "MISSING_PARAM", message: "prompt is required")
        }

        var payload: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
        ]

        if let maxTokens = body["maxTokens"] as? Int {
            payload["options"] = ["num_predict": maxTokens]
        }

        let images = normalizedImages(from: body)
        if !images.isEmpty {
            payload["images"] = images
        }

        return payload
    }

    private func buildOllamaChatPayload(
        body: [String: Any],
        messages: [[String: Any]],
        model: String
    ) throws -> [String: Any] {
        var normalizedMessages = messages

        if let prompt = nonEmptyString(body["prompt"]) {
            normalizedMessages.append([
                "role": "user",
                "content": prompt,
            ])
        }

        guard !normalizedMessages.isEmpty else {
            throw AIHandlerError(code: "MISSING_PARAM", message: "messages or prompt is required")
        }

        return [
            "model": model,
            "messages": normalizedMessages,
            "stream": false,
        ]
    }

    private func postOllama(
        path: String,
        payload: [String: Any]?,
        endpoint: String,
        method: String = "POST"
    ) async throws -> [String: Any] {
        guard let baseURL = URL(string: endpoint) else {
            throw AIHandlerError(code: "INVALID_PARAM", message: "ollamaEndpoint must be a valid URL")
        }

        let url = baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30

        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIHandlerError(code: "OLLAMA_DISCONNECTED", message: "Invalid response from Ollama")
            }

            if !(200...299).contains(httpResponse.statusCode) {
                let message = String(data: data, encoding: .utf8) ?? "Ollama request failed"
                let code = httpResponse.statusCode == 404 ? "OLLAMA_MODEL_NOT_FOUND" : "OLLAMA_DISCONNECTED"
                throw AIHandlerError(code: code, message: message)
            }

            if data.isEmpty {
                return [:]
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AIHandlerError(code: "OLLAMA_DISCONNECTED", message: "Ollama returned invalid JSON")
            }

            return json
        } catch let error as AIHandlerError {
            throw error
        } catch {
            throw AIHandlerError(code: "OLLAMA_DISCONNECTED", message: "Lost connection to Ollama during inference")
        }
    }

    private func composePrompt(from body: [String: Any]) -> String {
        let prompt = nonEmptyString(body["prompt"])
        let text = nonEmptyString(body["text"])

        switch (prompt, text) {
        case let (.some(prompt), .some(text)):
            return "\(prompt)\n\nContext:\n\(text)"
        case let (.some(prompt), nil):
            return prompt
        case let (nil, .some(text)):
            return text
        default:
            return ""
        }
    }

    private func normalizedImages(from body: [String: Any]) -> [String] {
        if let images = body["images"] as? [String] {
            return images.filter { !$0.isEmpty }
        }

        if let image = body["image"] as? String, !image.isEmpty {
            return [image]
        }

        return []
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedOllamaEndpoint(_ endpoint: String?) -> String {
        let trimmed = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = trimmed.isEmpty ? AIState.defaultOllamaEndpoint : trimmed
        return base.hasSuffix("/") ? String(base.dropLast()) : base
    }

    private func elapsedMs(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

private struct AIHandlerError: Error {
    let code: String
    let message: String

    var response: [String: Any] {
        errorResponse(code: code, message: message)
    }
}

private final class StubAudioRecorder {
    struct Result {
        let audio: Data
        let durationMs: Int
    }

    let engine = AVAudioEngine()
    private(set) var isRecording = false
    private var startedAt: Date?

    var elapsedMs: Int {
        guard let startedAt else { return 0 }
        return Int(Date().timeIntervalSince(startedAt) * 1000)
    }

    func start() throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }
        engine.prepare()
        startedAt = Date()
        isRecording = true
    }

    func stop() throws -> Result {
        guard isRecording else { throw RecorderError.notRecording }
        let duration = elapsedMs
        engine.stop()
        startedAt = nil
        isRecording = false
        return Result(audio: Data(), durationMs: duration)
    }
}

private enum RecorderError: Error {
    case alreadyRecording
    case notRecording

    var response: [String: Any] {
        switch self {
        case .alreadyRecording:
            return errorResponse(code: "RECORDING_ALREADY_ACTIVE", message: "Recording is already active")
        case .notRecording:
            return errorResponse(code: "NO_RECORDING_ACTIVE", message: "No recording is active")
        }
    }
}
