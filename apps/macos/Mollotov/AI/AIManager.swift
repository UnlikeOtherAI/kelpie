import Foundation

/// Thin Swift wrapper around the core-ai C library.
/// All methods are synchronous — AIState wraps them in Task{} for async.
final class AIManager {
    private let ref: MollotovAiManagerRef

    init(modelsDir: String) {
        ref = mollotov_ai_create(modelsDir)!
    }

    deinit {
        mollotov_ai_destroy(ref)
    }

    // MARK: - HF Token

    var hfToken: String {
        get { string(mollotov_ai_get_hf_token(ref)) }
        set { mollotov_ai_set_hf_token(ref, newValue) }
    }

    // MARK: - Model Catalog

    func listApprovedModels() -> [[String: Any]] {
        guard let raw = mollotov_ai_list_approved_models(ref) else { return [] }
        defer { mollotov_ai_free_string(raw) }
        let str = String(cString: raw)
        guard let data = str.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr
    }

    func modelFitness(id: String, ramGB: Double, diskGB: Double) -> [String: Any] {
        guard let raw = mollotov_ai_model_fitness(ref, id, ramGB, diskGB) else { return [:] }
        defer { mollotov_ai_free_string(raw) }
        let str = String(cString: raw)
        guard let data = str.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return dict
    }

    // MARK: - Model Store

    func isModelDownloaded(id: String) -> Bool {
        mollotov_ai_is_model_downloaded(ref, id)
    }

    func modelPath(id: String) -> String {
        string(mollotov_ai_model_path(ref, id))
    }

    func removeModel(id: String) -> Bool {
        mollotov_ai_remove_model(ref, id)
    }

    /// Blocking download — call from a background thread/Task.
    /// Returns nil on success, error JSON string on failure.
    func downloadModel(id: String, progress: ((Int64, Int64) -> Void)?) -> String? {
        let cb: MollotovAiDownloadProgressCb?
        var progressClosure = progress

        if progress != nil {
            cb = { downloaded, total, userData in
                guard let ptr = userData else { return }
                let closure = ptr.assumingMemoryBound(to: ((Int64, Int64) -> Void)?.self).pointee
                closure?(downloaded, total)
            }
        } else {
            cb = nil
        }

        let result: UnsafeMutablePointer<CChar>?
        if cb != nil {
            result = withUnsafeMutablePointer(to: &progressClosure) { ptr in
                mollotov_ai_download_model(ref, id, cb, ptr)
            }
        } else {
            result = mollotov_ai_download_model(ref, id, nil, nil)
        }

        guard let result else { return nil }  // nil = success
        defer { mollotov_ai_free_string(result) }
        return String(cString: result)
    }

    // MARK: - Ollama

    func setOllamaEndpoint(_ endpoint: String) {
        mollotov_ai_set_ollama_endpoint(ref, endpoint)
    }

    func ollamaReachable() -> Bool {
        mollotov_ai_ollama_reachable(ref)
    }

    func ollamaListModels() -> [[String: Any]] {
        guard let raw = mollotov_ai_ollama_list_models(ref) else { return [] }
        defer { mollotov_ai_free_string(raw) }
        let str = String(cString: raw)
        guard let data = str.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr
    }

    func ollamaInfer(model: String, requestJSON: String) -> [String: Any] {
        guard let raw = mollotov_ai_ollama_infer(ref, model, requestJSON) else { return [:] }
        defer { mollotov_ai_free_string(raw) }
        let str = String(cString: raw)
        guard let data = str.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return dict
    }

    // MARK: - HF Cloud

    func hfCloudInfer(modelId: String, requestJSON: String) -> [String: Any] {
        guard let raw = mollotov_ai_hf_infer(ref, modelId, requestJSON) else { return [:] }
        defer { mollotov_ai_free_string(raw) }
        let str = String(cString: raw)
        guard let data = str.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return dict
    }

    // MARK: - Private

    private func string(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
        guard let ptr else { return "" }
        defer { mollotov_ai_free_string(ptr) }
        return String(cString: ptr)
    }
}
