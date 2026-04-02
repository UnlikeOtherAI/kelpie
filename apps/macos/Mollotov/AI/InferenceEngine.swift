import Foundation

/// Process-level singleton. Heavy work stays off the main thread.
final class InferenceEngine: ObservableObject, @unchecked Sendable {
    static let shared = InferenceEngine()

    @MainActor @Published private(set) var isLoaded = false
    @MainActor @Published private(set) var modelName: String?
    @MainActor @Published private(set) var capabilities: [String] = []

    private let queue = DispatchQueue(label: "com.mollotov.inference", qos: .userInitiated)
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var loadedModelName: String?
    private var loadedCapabilities: [String] = []
    private var estimatedMemoryUsageMB = 0

    struct InferenceResult {
        let text: String
        let tokensUsed: Int
        let inferenceTimeMs: Int
    }

    enum InferenceError: Error {
        case noModelLoaded
        case alreadyLoaded(current: String)
        case loadFailed(String)
        case inferenceFailed(String)
        case visionNotSupported
        case audioNotSupported
    }

    private init() {}

    func load(path: String, name: String, capabilities: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                if let current = self.loadedModelName {
                    continuation.resume(throwing: InferenceError.alreadyLoaded(current: current))
                    return
                }

                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    continuation.resume(throwing: InferenceError.loadFailed("No model file found at \(path)"))
                    return
                }

                // TODO: Replace with llama.cpp model/context loading.
                // Until llama.cpp is linked, reject the load so ai-status never
                // reports isLoaded=true while infer always throws.
                continuation.resume(throwing: InferenceError.loadFailed(
                    "Native inference is not available until the llama.cpp package is linked."
                ))
            }
        }
    }

    func unload() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                // TODO: Replace with llama_free / llama_model_free once the package is linked.
                self.ctx = nil
                self.model = nil
                self.loadedModelName = nil
                self.loadedCapabilities = []
                self.estimatedMemoryUsageMB = 0

                Task { @MainActor in
                    self.isLoaded = false
                    self.modelName = nil
                    self.capabilities = []
                }

                continuation.resume()
            }
        }
    }

    func infer(
        prompt: String,
        audio: Data? = nil,
        image: Data? = nil,
        maxTokens: Int = 512,
        temperature: Float = 0.7
    ) async throws -> InferenceResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<InferenceResult, Error>) in
            queue.async {
                guard self.loadedModelName != nil else {
                    continuation.resume(throwing: InferenceError.noModelLoaded)
                    return
                }
                if image != nil && !self.loadedCapabilities.contains("vision") {
                    continuation.resume(throwing: InferenceError.visionNotSupported)
                    return
                }
                if audio != nil && !self.loadedCapabilities.contains("audio") {
                    continuation.resume(throwing: InferenceError.audioNotSupported)
                    return
                }

                let startedAt = DispatchTime.now()

                _ = prompt
                _ = maxTokens
                _ = temperature

                // TODO: Replace with llama.cpp tokenization, sampling, and decoding.
                let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds
                continuation.resume(throwing: InferenceError.inferenceFailed(
                    "Native inference is not available until the llama.cpp package is linked."
                ))
                _ = elapsed
            }
        }
    }

    var memoryUsageMB: Int {
        queue.sync {
            estimatedMemoryUsageMB
        }
    }
}
