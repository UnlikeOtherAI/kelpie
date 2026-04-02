import Foundation

private actor AIBackendStore {
    static let shared = AIBackendStore()

    struct Snapshot {
        let backend: String?
        let model: String?
        let capabilities: [String]
        let ollamaEndpoint: String?
    }

    private var backend: String?
    private var model: String?
    private var capabilities: [String] = []
    private var ollamaEndpoint: String?

    func setNative(model: String, capabilities: [String]) {
        backend = "native"
        self.model = model
        self.capabilities = capabilities
        ollamaEndpoint = nil
    }

    func setOllama(model: String, endpoint: String, capabilities: [String]) {
        backend = "ollama"
        self.model = model
        self.capabilities = capabilities
        ollamaEndpoint = endpoint
    }

    func clear() {
        backend = nil
        model = nil
        capabilities = []
        ollamaEndpoint = nil
    }

    func snapshot() -> Snapshot {
        Snapshot(backend: backend, model: model, capabilities: capabilities, ollamaEndpoint: ollamaEndpoint)
    }
}

struct AIHandler {
    let context: HandlerContext

    private let engine = InferenceEngine.shared
    private let backendStore = AIBackendStore.shared
    @MainActor private static let recorder = AudioRecorder()

    private enum NativeModelResolution {
        case success(path: String, name: String, capabilities: [String])
        case failure([String: Any])
    }

    func register(on router: Router) {
        router.register("ai-status") { _ in await status() }
        router.register("ai-load") { body in await load(body) }
        router.register("ai-unload") { _ in await unload() }
        router.register("ai-infer") { body in await infer(body) }
        router.register("ai-record") { body in await record(body) }
    }

    private func status() async -> [String: Any] {
        let nativeState = await MainActor.run {
            (
                loaded: engine.isLoaded,
                model: engine.modelName,
                capabilities: engine.capabilities
            )
        }
        let backendState = await backendStore.snapshot()

        if nativeState.loaded, let model = nativeState.model {
            return successResponse([
                "loaded": true,
                "model": model,
                "backend": "native",
                "capabilities": nativeState.capabilities,
                "memoryUsageMB": engine.memoryUsageMB,
            ])
        }

        if backendState.backend == "ollama", let model = backendState.model {
            return successResponse([
                "loaded": true,
                "model": model,
                "backend": "ollama",
                "capabilities": backendState.capabilities,
                "ollamaEndpoint": backendState.ollamaEndpoint ?? defaultOllamaEndpoint,
            ])
        }

        return successResponse(["loaded": false])
    }

    private func load(_ body: [String: Any]) async -> [String: Any] {
        let start = DispatchTime.now()

        if let model = body["model"] as? String, model.hasPrefix("ollama:") {
            let endpoint = (body["ollamaEndpoint"] as? String) ?? defaultOllamaEndpoint
            let ollamaModel = String(model.dropFirst("ollama:".count))
            let reachable = await isOllamaReachable(endpoint: endpoint)
            guard reachable else {
                return errorResponse(
                    code: "OLLAMA_NOT_AVAILABLE",
                    message: "Ollama is not running at \(endpoint)"
                )
            }

            await engine.unload()
            let capabilities = ollamaCapabilities(for: ollamaModel)
            await backendStore.setOllama(model: ollamaModel, endpoint: endpoint, capabilities: capabilities)
            await MainActor.run {
                AIState.shared.enableOllamaOnly()
            }
            return successResponse([
                "model": ollamaModel,
                "backend": "ollama",
                "loadTimeMs": elapsedMs(since: start),
            ])
        }

        let isAppleSilicon = await MainActor.run { AIState.shared.isAppleSilicon }
        guard isAppleSilicon else {
            return errorResponse(
                code: "PLATFORM_NOT_SUPPORTED",
                message: "Native inference requires Apple Silicon. Load an Ollama model instead."
            )
        }

        let resolution = resolveNativeModel(from: body)
        switch resolution {
        case .failure(let error):
            return error
        case .success(let path, let name, let capabilities):
            do {
                let nativeState = await MainActor.run { (engine.isLoaded, engine.modelName) }
                if nativeState.0 {
                    await engine.unload()
                }

                try await engine.load(path: path, name: name, capabilities: capabilities)
                await backendStore.setNative(model: name, capabilities: capabilities)
                return successResponse([
                    "model": name,
                    "backend": "native",
                    "loadTimeMs": elapsedMs(since: start),
                ])
            } catch let error as InferenceEngine.InferenceError {
                return mapInferenceError(error)
            } catch {
                return errorResponse(code: "LOAD_FAILED", message: error.localizedDescription)
            }
        }
    }

    private func unload() async -> [String: Any] {
        await engine.unload()
        await backendStore.clear()
        return successResponse()
    }

    private func infer(_ body: [String: Any]) async -> [String: Any] {
        let backendState = await backendStore.snapshot()
        let nativeLoaded = await MainActor.run { engine.isLoaded }
        guard nativeLoaded || backendState.backend == "ollama" else {
            return errorResponse(code: "NO_MODEL_LOADED", message: "Load a model first with ai-load")
        }

        let maxTokens = body["maxTokens"] as? Int ?? 512
        let temperature = body["temperature"] as? Double ?? 0.7
        let prompt = body["prompt"] as? String ?? ""
        let explicitText = body["text"] as? String
        let contextMode = body["context"] as? String
        let audio = decodeBase64Field(body["audio"])
        let messages = body["messages"] as? [[String: Any]]

        if backendState.backend == "ollama" {
            guard let model = backendState.model else {
                return errorResponse(code: "NO_MODEL_LOADED", message: "Load a model first with ai-load")
            }
            guard audio == nil else {
                return errorResponse(
                    code: "AUDIO_NOT_SUPPORTED",
                    message: "Model does not support audio. Transcribe via platform STT and resend as text."
                )
            }

            do {
                let fallbackContext = await preloadedContext(mode: contextMode)
                let contextText = explicitText ?? fallbackContext
                let image = contextMode == "screenshot" ? try await screenshotData() : nil
                let result = try await inferWithOllama(
                    endpoint: backendState.ollamaEndpoint ?? defaultOllamaEndpoint,
                    model: model,
                    prompt: prompt,
                    messages: messages,
                    contextText: contextText,
                    image: image
                )
                return successResponse([
                    "response": result.text,
                    "tokensUsed": result.tokensUsed,
                    "inferenceTimeMs": result.inferenceTimeMs,
                ])
            } catch {
                return errorResponse(code: "OLLAMA_DISCONNECTED", message: error.localizedDescription)
            }
        }

        let capabilities = await MainActor.run { engine.capabilities }
        if audio != nil && !capabilities.contains("audio") {
            return errorResponse(
                code: "AUDIO_NOT_SUPPORTED",
                message: "Model does not support audio. Transcribe via platform STT and resend as text."
            )
        }

        if contextMode == "screenshot" {
            do {
                let image = try await screenshotData()
                let nativePrompt = buildNativeSingleShotPrompt(prompt: prompt, extraContext: nil)
                let result = try await engine.infer(
                    prompt: nativePrompt,
                    audio: audio,
                    image: image,
                    maxTokens: maxTokens,
                    temperature: Float(temperature)
                )
                let parsed = parseResponseJSON(result.text)
                var response = successResponse([
                    "response": parsed.answer,
                    "tokensUsed": result.tokensUsed,
                    "inferenceTimeMs": result.inferenceTimeMs,
                ])
                if let transcription = parsed.transcription {
                    response["transcription"] = transcription
                }
                return response
            } catch let error as InferenceEngine.InferenceError {
                return mapInferenceError(error)
            } catch {
                return errorResponse(code: "INFERENCE_FAILED", message: error.localizedDescription)
            }
        }

        do {
            let fallbackContext = await preloadedContext(mode: contextMode)
            let preloaded = explicitText ?? fallbackContext
            let harness = InferenceHarness(context: context)
            let result = try await harness.run(prompt: prompt, audio: audio, preloadedContext: preloaded)

            var response = successResponse([
                "response": result.answer,
                "tokensUsed": result.totalTokens,
                "inferenceTimeMs": result.totalTimeMs,
            ])
            if let transcription = result.transcription {
                response["transcription"] = transcription
            }
            return response
        } catch let error as InferenceEngine.InferenceError {
            return mapInferenceError(error)
        } catch {
            return errorResponse(code: "INFERENCE_FAILED", message: error.localizedDescription)
        }
    }

    private func record(_ body: [String: Any]) async -> [String: Any] {
        let action = body["action"] as? String ?? "status"

        switch action {
        case "start":
            let state = await MainActor.run { (AIHandler.recorder.isRecording, AIHandler.recorder.hasPendingAudio) }
            guard !state.0 else {
                return errorResponse(
                    code: "RECORDING_ALREADY_ACTIVE",
                    message: "Stop the current recording before starting a new one."
                )
            }

            do {
                try await MainActor.run {
                    try AIHandler.recorder.start()
                }
                return successResponse(["recording": true])
            } catch let error as AudioRecorder.RecordingError {
                return mapRecordingError(error)
            } catch {
                return errorResponse(code: "RECORDING_FAILED", message: error.localizedDescription)
            }

        case "stop":
            let state = await MainActor.run { (AIHandler.recorder.isRecording, AIHandler.recorder.hasPendingAudio) }
            guard state.0 || state.1 else {
                return errorResponse(
                    code: "NO_RECORDING_ACTIVE",
                    message: "Start recording first."
                )
            }

            let result = await MainActor.run { () -> (audio: Data, elapsedMs: Int) in
                let audio = AIHandler.recorder.stop()
                return (audio, AIHandler.recorder.elapsedMs)
            }
            return successResponse([
                "audio": result.audio.base64EncodedString(),
                "durationMs": result.elapsedMs,
            ])

        case "status":
            let state = await MainActor.run {
                (
                    recording: AIHandler.recorder.isRecording,
                    elapsedMs: AIHandler.recorder.elapsedMs
                )
            }
            return successResponse([
                "recording": state.recording,
                "elapsedMs": state.elapsedMs,
            ])

        default:
            return errorResponse(code: "INVALID_PARAM", message: "Unknown action: \(action)")
        }
    }

    private func resolveNativeModel(from body: [String: Any]) -> NativeModelResolution {
        if let path = body["path"] as? String, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .failure(errorResponse(code: "MODEL_NOT_FOUND", message: "No GGUF file at specified path"))
            }

            let metadata = nativeMetadata(forModelAt: url)
            let name = metadata.name ?? url.deletingPathExtension().lastPathComponent
            return .success(path: url.path, name: name, capabilities: metadata.capabilities)
        }

        guard let model = body["model"] as? String, !model.isEmpty else {
            return .failure(errorResponse(code: "MISSING_PARAM", message: "model or path is required"))
        }

        let modelURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mollotov/models/\(model)/model.gguf")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            return .failure(errorResponse(code: "MODEL_NOT_FOUND", message: "No GGUF file at specified path"))
        }

        let metadata = nativeMetadata(forModelAt: modelURL)
        return .success(path: modelURL.path, name: metadata.name ?? model, capabilities: metadata.capabilities)
    }

    private func nativeMetadata(forModelAt url: URL) -> (name: String?, capabilities: [String]) {
        let metadataURL = url.deletingLastPathComponent().appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, ["text"])
        }
        let name = raw["name"] as? String
        let capabilities = raw["capabilities"] as? [String] ?? ["text"]
        return (name, capabilities.isEmpty ? ["text"] : capabilities)
    }

    @MainActor
    private func preloadedContext(mode: String?) async -> String? {
        switch mode {
        case nil:
            return nil

        case "page_text":
            return (try? await context.evaluateJSReturningString(
                """
                JSON.stringify((function() {
                    var el = document.body || document.documentElement;
                    var text = (el?.innerText || el?.textContent || '').trim();
                    return {
                        title: document.title || '',
                        url: location.href || '',
                        content: text,
                        wordCount: text ? text.split(/\\s+/).length : 0
                    };
                })())
                """
            )) ?? ""

        case "dom":
            return (try? await context.evaluateJSReturningString(
                """
                JSON.stringify((function() {
                    var el = document.body || document.documentElement;
                    return { html: el ? el.outerHTML : '', selector: 'body' };
                })())
                """
            )) ?? ""

        case "accessibility":
            return (try? await context.evaluateJSReturningString(
                """
                JSON.stringify((function() {
                    function walk(node, depth) {
                        if (!node || depth > 3) return null;
                        var entry = {
                            role: node.getAttribute('role') || node.tagName.toLowerCase(),
                            name: (node.getAttribute('aria-label') || node.textContent || '').trim().substring(0, 80)
                        };
                        var children = [];
                        for (var child of node.children) {
                            var childResult = walk(child, depth + 1);
                            if (childResult) children.push(childResult);
                        }
                        if (children.length) entry.children = children;
                        return entry;
                    }
                    return walk(document.body, 0);
                })())
                """
            )) ?? ""

        case "screenshot":
            return nil

        default:
            return nil
        }
    }

    @MainActor
    private func screenshotData() async throws -> Data {
        let image = try await context.takeSnapshot()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "AIHandler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode screenshot"])
        }
        return png
    }

    private func inferWithOllama(
        endpoint: String,
        model: String,
        prompt: String,
        messages: [[String: Any]]?,
        contextText: String?,
        image: Data?
    ) async throws -> InferenceEngine.InferenceResult {
        let startedAt = DispatchTime.now()
        let userPrompt = merge(prompt: prompt, contextText: contextText)

        if let messages, !messages.isEmpty {
            let url = try ollamaURL(endpoint: endpoint, path: "/api/chat")
            var requestMessages = messages
            var userMessage: [String: Any] = ["role": "user", "content": userPrompt]
            if let image {
                userMessage["images"] = [image.base64EncodedString()]
            }
            requestMessages.append(userMessage)

            let payload: [String: Any] = [
                "model": model,
                "messages": requestMessages,
                "stream": false,
            ]
            let response = try await postJSON(url: url, payload: payload)
            let message = response["message"] as? [String: Any]
            let text = message?["content"] as? String ?? ""
            let duration = parseDurationMs(response["total_duration"])
            return InferenceEngine.InferenceResult(
                text: text,
                tokensUsed: response["eval_count"] as? Int ?? approximateTokens(for: text),
                inferenceTimeMs: duration ?? elapsedMs(since: startedAt)
            )
        }

        let url = try ollamaURL(endpoint: endpoint, path: "/api/generate")
        var payload: [String: Any] = [
            "model": model,
            "prompt": userPrompt,
            "stream": false,
        ]
        if let image {
            payload["images"] = [image.base64EncodedString()]
        }
        let response = try await postJSON(url: url, payload: payload)
        let text = response["response"] as? String ?? ""
        let duration = parseDurationMs(response["total_duration"])
        return InferenceEngine.InferenceResult(
            text: text,
            tokensUsed: response["eval_count"] as? Int ?? approximateTokens(for: text),
            inferenceTimeMs: duration ?? elapsedMs(since: startedAt)
        )
    }

    private func postJSON(url: URL, payload: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "AIHandler", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Lost connection to Ollama during inference"
            ])
        }

        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func isOllamaReachable(endpoint: String) async -> Bool {
        guard let url = try? ollamaURL(endpoint: endpoint, path: "/api/tags") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return 200..<300 ~= http.statusCode
        } catch {
            return false
        }
    }

    private func ollamaURL(endpoint: String, path: String) throws -> URL {
        guard let base = URL(string: endpoint) else {
            throw NSError(domain: "AIHandler", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid Ollama endpoint"])
        }
        return base.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func ollamaCapabilities(for model: String) -> [String] {
        let lowercased = model.lowercased()
        if lowercased.contains("llava") || lowercased.contains("bakllava") || lowercased.contains("moondream") {
            return ["text", "vision"]
        }
        return ["text"]
    }

    private func buildNativeSingleShotPrompt(prompt: String, extraContext: String?) -> String {
        var sections = [SystemPrompt.build()]
        if let extraContext, !extraContext.isEmpty {
            sections.append("")
            sections.append("Context:")
            sections.append(extraContext)
        }
        sections.append("")
        sections.append("User question:")
        sections.append(prompt)
        return sections.joined(separator: "\n")
    }

    private func merge(prompt: String, contextText: String?) -> String {
        guard let contextText, !contextText.isEmpty else { return prompt }
        return """
        \(prompt)

        Context:
        \(contextText)
        """
    }

    private func parseResponseJSON(_ text: String) -> (answer: String, transcription: String?) {
        guard let range = text.range(of: "\\{.*\\}", options: .regularExpression),
              let data = String(text[range]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (text, nil)
        }
        return (
            object["answer"] as? String ?? object["response"] as? String ?? text,
            object["transcription"] as? String
        )
    }

    private func mapInferenceError(_ error: InferenceEngine.InferenceError) -> [String: Any] {
        switch error {
        case .noModelLoaded:
            return errorResponse(code: "NO_MODEL_LOADED", message: "Load a model first with ai-load")
        case .alreadyLoaded(let current):
            return errorResponse(code: "MODEL_ALREADY_LOADED", message: "A model is already loaded: \(current)")
        case .loadFailed(let message):
            return errorResponse(code: "LOAD_FAILED", message: message)
        case .inferenceFailed(let message):
            return errorResponse(code: "INFERENCE_FAILED", message: message)
        case .visionNotSupported:
            return errorResponse(code: "VISION_NOT_SUPPORTED", message: "Model does not support image input.")
        case .audioNotSupported:
            return errorResponse(
                code: "AUDIO_NOT_SUPPORTED",
                message: "Model does not support audio. Transcribe via platform STT and resend as text."
            )
        }
    }

    private func mapRecordingError(_ error: AudioRecorder.RecordingError) -> [String: Any] {
        switch error {
        case .alreadyActive:
            return errorResponse(code: "RECORDING_ALREADY_ACTIVE", message: "Stop the current recording first.")
        case .permissionDenied:
            return errorResponse(code: "MIC_PERMISSION_DENIED", message: "Microphone permission was denied.")
        case .configurationFailed(let message):
            return errorResponse(code: "RECORDING_FAILED", message: message)
        }
    }

    private func decodeBase64Field(_ value: Any?) -> Data? {
        guard let string = value as? String else { return nil }
        return Data(base64Encoded: string)
    }

    private func parseDurationMs(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue > 1_000_000 ? intValue / 1_000_000 : intValue
        }
        if let doubleValue = value as? Double {
            return doubleValue > 1_000_000 ? Int(doubleValue / 1_000_000.0) : Int(doubleValue)
        }
        return nil
    }

    private func approximateTokens(for text: String) -> Int {
        max(1, text.count / 4)
    }

    private func elapsedMs(since startedAt: DispatchTime) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000)
    }

    private let defaultOllamaEndpoint = "http://localhost:11434"
}
