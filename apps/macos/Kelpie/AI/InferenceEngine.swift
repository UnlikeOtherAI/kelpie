import Foundation
import llama

/// Process-level singleton. Heavy work stays off the main thread.
final class InferenceEngine: ObservableObject, @unchecked Sendable {
    static let shared = InferenceEngine()

    @MainActor @Published private(set) var isLoaded = false
    @MainActor @Published private(set) var modelName: String?
    @MainActor @Published private(set) var capabilities: [String] = []

    private let queue = DispatchQueue(label: "com.kelpie.inference", qos: .userInitiated)
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
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

    private static var backendInitialized = false

    private init() {}

    func load(path: String, name: String, capabilities: [String]) async throws {
        // Auto-unload previous model if any
        let currentlyLoaded = await MainActor.run { isLoaded }
        if currentlyLoaded {
            await unload()
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    continuation.resume(throwing: InferenceError.loadFailed("No model file found at \(path)"))
                    return
                }

                if !Self.backendInitialized {
                    llama_backend_init()
                    Self.backendInitialized = true
                }

                var modelParams = llama_model_default_params()
                modelParams.n_gpu_layers = 99 // offload everything to Metal

                guard let newModel = llama_model_load_from_file(path, modelParams) else {
                    continuation.resume(throwing: InferenceError.loadFailed("llama_model_load_from_file failed for \(path)"))
                    return
                }

                let nThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
                var ctxParams = llama_context_default_params()
                ctxParams.n_ctx = 8192
                ctxParams.n_threads = Int32(nThreads)
                ctxParams.n_threads_batch = Int32(nThreads)

                guard let newCtx = llama_init_from_model(newModel, ctxParams) else {
                    llama_model_free(newModel)
                    continuation.resume(throwing: InferenceError.loadFailed("Failed to create llama context"))
                    return
                }

                self.model = newModel
                self.ctx = newCtx
                self.vocab = llama_model_get_vocab(newModel)
                self.loadedModelName = name
                self.loadedCapabilities = capabilities
                self.estimatedMemoryUsageMB = Int(llama_model_size(newModel) / (1024 * 1024))

                Task { @MainActor in
                    self.isLoaded = true
                    self.modelName = name
                    self.capabilities = capabilities
                }

                continuation.resume()
            }
        }
    }

    func unload() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if let ctx = self.ctx {
                    llama_free(ctx)
                }
                if let model = self.model {
                    llama_model_free(model)
                }

                self.ctx = nil
                self.model = nil
                self.vocab = nil
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
                guard let model = self.model, let ctx = self.ctx, let vocab = self.vocab else {
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

                // Tokenize
                let utf8Count = prompt.utf8.count
                let maxTokenCount = utf8Count + 2
                let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: maxTokenCount)
                defer { tokens.deallocate() }

                let tokenCount = llama_tokenize(vocab, prompt, Int32(utf8Count), tokens, Int32(maxTokenCount), true, false)
                guard tokenCount > 0 else {
                    continuation.resume(throwing: InferenceError.inferenceFailed("Tokenization failed"))
                    return
                }

                // Clear KV cache
                llama_memory_clear(llama_get_memory(ctx), false)

                // Prepare batch for prompt
                var batch = llama_batch_init(Int32(tokenCount), 0, 1)
                defer { llama_batch_free(batch) }

                for i in 0..<Int(tokenCount) {
                    batch.token[i] = tokens[i]
                    batch.pos[i] = Int32(i)
                    batch.n_seq_id[i] = 1
                    batch.seq_id[i]![0] = 0
                    batch.logits[i] = 0
                }
                batch.n_tokens = tokenCount
                batch.logits[Int(tokenCount) - 1] = 1

                guard llama_decode(ctx, batch) == 0 else {
                    continuation.resume(throwing: InferenceError.inferenceFailed("Initial decode failed"))
                    return
                }

                // Set up sampler
                let sparams = llama_sampler_chain_default_params()
                let sampler = llama_sampler_chain_init(sparams)!
                defer { llama_sampler_free(sampler) }

                llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature))
                llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

                // Generate tokens
                var output: [CChar] = []
                var generatedCount: Int32 = 0
                var curPos = tokenCount

                for _ in 0..<maxTokens {
                    let newTokenId = llama_sampler_sample(sampler, ctx, batch.n_tokens - 1)

                    if llama_vocab_is_eog(vocab, newTokenId) {
                        break
                    }

                    // Convert token to text
                    let pieceChars = self.tokenToPiece(vocab: vocab, token: newTokenId)
                    output.append(contentsOf: pieceChars)
                    generatedCount += 1

                    // Prepare next batch
                    batch.n_tokens = 0
                    batch.token[0] = newTokenId
                    batch.pos[0] = curPos
                    batch.n_seq_id[0] = 1
                    batch.seq_id[0]![0] = 0
                    batch.logits[0] = 1
                    batch.n_tokens = 1
                    curPos += 1

                    guard llama_decode(ctx, batch) == 0 else {
                        break
                    }
                }

                let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds
                let elapsedMs = Int(elapsed / 1_000_000)

                // Build output string
                output.append(0) // null terminator
                let resultText = String(cString: output)

                continuation.resume(returning: InferenceResult(
                    text: resultText,
                    tokensUsed: Int(generatedCount),
                    inferenceTimeMs: elapsedMs
                ))
            }
        }
    }

    var memoryUsageMB: Int {
        queue.sync { estimatedMemoryUsageMB }
    }

    private func tokenToPiece(vocab: OpaquePointer, token: llama_token) -> [CChar] {
        let bufSize = 8
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: bufSize)
        result.initialize(repeating: 0, count: bufSize)
        defer { result.deallocate() }

        let nTokens = llama_token_to_piece(vocab, token, result, Int32(bufSize), 0, false)

        if nTokens < 0 {
            let newSize = Int(-nTokens)
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: newSize)
            newResult.initialize(repeating: 0, count: newSize)
            defer { newResult.deallocate() }
            let nNew = llama_token_to_piece(vocab, token, newResult, Int32(newSize), 0, false)
            guard nNew > 0 else { return [] }
            return Array(UnsafeBufferPointer(start: newResult, count: Int(nNew)))
        } else {
            return Array(UnsafeBufferPointer(start: result, count: Int(nTokens)))
        }
    }
}
