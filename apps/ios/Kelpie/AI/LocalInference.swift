import Foundation

/// The same bounded, cancellable GGUF runtime used by Android and Windows.
final class LocalInference: @unchecked Sendable {
    static let shared = LocalInference()
    private let engine = kelpie_local_create()
    private let queue = DispatchQueue(label: "kelpie.local-inference", qos: .userInitiated, attributes: .concurrent)

    deinit { kelpie_local_destroy(engine) }

    func cancel() { kelpie_local_cancel(engine) }

    func execute(_ operation: String, body: [String: Any] = [:]) async -> [String: Any] {
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let input = String(data: data, encoding: .utf8) else {
            return errorResponse(code: "INVALID_PARAM", message: "Invalid inference parameters")
        }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let raw = kelpie_local_execute(engine, operation, input) else {
                    continuation.resume(returning: errorResponse(code: "AI_UNAVAILABLE", message: "Local inference is unavailable"))
                    return
                }
                defer { kelpie_ai_free_string(raw) }
                let result = (try? JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8))) as? [String: Any]
                continuation.resume(returning: result ?? errorResponse(code: "AI_INFERENCE_FAILED", message: "Invalid inference result"))
            }
        }
    }

    func load(_ body: [String: Any]) async -> [String: Any] {
        guard let path = body["model"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "model is required")
        }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.uint64Value else {
            return errorResponse(code: "MODEL_NOT_FOUND", message: "Select an existing GGUF model file")
        }
        #if targetEnvironment(simulator)
        // The simulator has no iOS process memory budget; os_proc_available_memory returns zero.
        let availableMemory = ProcessInfo.processInfo.physicalMemory / 2
        #else
        let availableMemory = UInt64(os_proc_available_memory())
        #endif
        if size * 3 / 2 + 256 * 1024 * 1024 > availableMemory {
            return errorResponse(code: "MODEL_MEMORY_LIMIT", message: "Use a smaller GGUF model or a LAN inference endpoint")
        }
        let result = await execute("load", body: body)
        if result["success"] as? Bool == true {
            await OpenAIEndpointService.shared.clearActive()
            await MainActor.run { AIState.shared.activateNative(model: path) }
        }
        return result
    }

    func importModel(_ url: URL) async throws -> String {
        try await Task.detached {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("local-models", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(UUID().uuidString + ".gguf")
            do {
                let input = try FileHandle(forReadingFrom: url)
                defer { try? input.close() }
                guard try input.read(upToCount: 4) == Data("GGUF".utf8) else {
                    throw NSError(domain: "LocalInference", code: 1, userInfo: [NSLocalizedDescriptionKey: "Select a GGUF model file"])
                }
                try FileManager.default.copyItem(at: url, to: file)
                try FileProtection.setComplete(at: file)
                return file.path
            } catch {
                try? FileManager.default.removeItem(at: file)
                throw error
            }
        }.value
    }
}
