import Foundation

actor AIBackendStore {
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

/// AI inference + audio-recording HTTP request handler.
///
/// Implementation is split across three files along functional seams:
/// - this file holds the type, request dispatch (`register`), and the
///   short-bodied request handlers (`status`, `load`, `unload`, `record`)
///   plus the error-mapping helpers shared by every backend;
/// - `AIHandler+Inference.swift` holds the `infer` flow, native-model
///   resolution, page-context preloading, and screenshot capture;
/// - `AIHandler+Ollama.swift` holds the Ollama transport layer.
struct AIHandler {
    let context: HandlerContext

    let engine = InferenceEngine.shared
    let backendStore = AIBackendStore.shared
    @MainActor private static let recorder = AudioRecorder()

    enum NativeModelResolution {
        case success(path: String, name: String, capabilities: [String])
        case failure([String: Any])
    }

    let defaultOllamaEndpoint = "http://localhost:11434"

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
                "memoryUsageMB": engine.memoryUsageMB
            ])
        }

        if backendState.backend == "ollama", let model = backendState.model {
            return successResponse([
                "loaded": true,
                "model": model,
                "backend": "ollama",
                "capabilities": backendState.capabilities,
                "ollamaEndpoint": backendState.ollamaEndpoint ?? defaultOllamaEndpoint
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
                "loadTimeMs": elapsedMs(since: start)
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
        case let .success(path, name, capabilities):
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
                    "loadTimeMs": elapsedMs(since: start)
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

    private func record(_ body: [String: Any]) async -> [String: Any] {
        let action = body["action"] as? String ?? "status"

        switch action {
        case "start":
            let state = await MainActor.run { (Self.recorder.isRecording, Self.recorder.hasPendingAudio) }
            guard !state.0 else {
                return errorResponse(
                    code: "RECORDING_ALREADY_ACTIVE",
                    message: "Stop the current recording before starting a new one."
                )
            }

            do {
                try await Self.recorder.start()
                return successResponse(["recording": true])
            } catch let error as AudioRecorder.RecordingError {
                return mapRecordingError(error)
            } catch {
                return errorResponse(code: "RECORDING_FAILED", message: error.localizedDescription)
            }

        case "stop":
            let state = await MainActor.run { (Self.recorder.isRecording, Self.recorder.hasPendingAudio) }
            guard state.0 || state.1 else {
                return errorResponse(
                    code: "NO_RECORDING_ACTIVE",
                    message: "Start recording first."
                )
            }

            let result = await MainActor.run { () -> (audio: Data, elapsedMs: Int) in
                let audio = Self.recorder.stop()
                return (audio, Self.recorder.elapsedMs)
            }
            return successResponse([
                "audio": result.audio.base64EncodedString(),
                "durationMs": result.elapsedMs
            ])

        case "status":
            let state = await MainActor.run {
                (
                    recording: Self.recorder.isRecording,
                    elapsedMs: Self.recorder.elapsedMs
                )
            }
            return successResponse([
                "recording": state.recording,
                "elapsedMs": state.elapsedMs
            ])

        default:
            return errorResponse(code: "INVALID_PARAM", message: "Unknown action: \(action)")
        }
    }

    // MARK: - Error mapping + shared utilities

    func mapInferenceError(_ error: InferenceEngine.InferenceError) -> [String: Any] {
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

    func decodeBase64Field(_ value: Any?) -> Data? {
        guard let string = value as? String else { return nil }
        return Data(base64Encoded: string)
    }

    func elapsedMs(since startedAt: DispatchTime) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000)
    }
}
