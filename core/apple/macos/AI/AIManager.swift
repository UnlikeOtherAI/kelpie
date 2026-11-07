import Foundation

/// Thin Swift wrapper around the core-ai C library.
/// All methods are synchronous — AIState wraps them in Task{} for async.
final class AIManager: @unchecked Sendable {
    private let ref: KelpieAiManagerRef
    private let modelsDirectoryURL: URL
    private var ollamaEndpoint = "http://localhost:11434"

    init(modelsDir: String) {
        modelsDirectoryURL = URL(fileURLWithPath: modelsDir, isDirectory: true)
        // swiftlint:disable:next force_unwrapping
        ref = kelpie_ai_create(modelsDir)!
    }

    deinit {
        kelpie_ai_destroy(ref)
    }

    // MARK: - HF Token

    var hfToken: String {
        get { string(kelpie_ai_get_hf_token(ref)) }
        set { kelpie_ai_set_hf_token(ref, newValue) }
    }

    // MARK: - Model Catalog

    func listApprovedModels() -> [[String: Any]] {
        guard let raw = kelpie_ai_list_approved_models(ref) else { return [] }
        defer { kelpie_ai_free_string(raw) }
        let str = String(cString: raw)
        guard let data = str.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr
    }

    func modelFitness(id: String, ramGB: Double, diskGB: Double) -> [String: Any] {
        guard let raw = kelpie_ai_model_fitness(ref, id, ramGB, diskGB) else { return [:] }
        defer { kelpie_ai_free_string(raw) }
        let str = String(cString: raw)
        guard let data = str.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return dict
    }

    // MARK: - Model Store

    func isModelDownloaded(id: String) -> Bool {
        let path = modelFileURL(for: id).path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return size > 1_000_000
    }

    func modelPath(id: String) -> String {
        modelFileURL(for: id).path
    }

    func removeModel(id: String) -> Bool {
        let directoryURL = modelDirectoryURL(for: id)
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return false
        }

        do {
            try FileManager.default.removeItem(at: directoryURL)
            return true
        } catch {
            return false
        }
    }

    /// Blocking download — call from a background thread/Task.
    /// Returns nil on success, error JSON string on failure.
    func downloadModel(id: String, progress: ((Int64, Int64) -> Void)?) -> String? {
        _ = progress

        guard let model = AIModelCatalog.approvedModel(id: id) else {
            return errorJSONString(
                code: "not_found",
                message: "Unknown model ID: \(id)"
            )
        }

        let directoryURL = modelDirectoryURL(for: id)
        let temporaryURL = directoryURL.appendingPathComponent("model.gguf.download")
        let finalURL = modelFileURL(for: id)

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            return errorJSONString(
                code: "filesystem",
                message: "Cannot create directory: \(directoryURL.path)"
            )
        }

        var request = URLRequest(url: model.downloadURL)
        if !hfToken.isEmpty {
            request.setValue("Bearer \(hfToken)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 600

        let downloadResult = synchronousDownload(request)
        switch downloadResult {
        case let .failure(error):
            return errorJSONString(code: "network", message: "Download failed: \(error.localizedDescription)")

        case let .success((location, response)):
            if let error = downloadHTTPError(for: response, tokenIsSet: !hfToken.isEmpty) {
                return error
            }

            return finalizeDownloadedModel(
                from: location,
                model: model,
                directoryURL: directoryURL,
                temporaryURL: temporaryURL,
                finalURL: finalURL
            )
        }
    }

    // MARK: - Ollama

    func setOllamaEndpoint(_ endpoint: String) {
        ollamaEndpoint = normalizeOllamaEndpoint(endpoint)
    }

    func ollamaReachable() -> Bool {
        guard let url = ollamaURL(path: "/api/tags") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2

        guard case let .success((_, response)) = synchronousDataRequest(request) else {
            return false
        }

        return 200..<300 ~= response.statusCode
    }

    func ollamaListModels() -> [[String: Any]] {
        guard let url = ollamaURL(path: "/api/tags") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        guard case let .success((data, response)) = synchronousDataRequest(request),
              200..<300 ~= response.statusCode,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = payload["models"] as? [[String: Any]] else {
            return []
        }

        return models.compactMap { model in
            guard let name = model["name"] as? String else { return nil }
            return [
                "name": name,
                "size": (model["size"] as? NSNumber)?.int64Value ?? 0,
                "capabilities": Self.ollamaCapabilities(for: name)
            ]
        }
    }

    func ollamaInfer(model: String, requestJSON: String) -> [String: Any] {
        guard let body = jsonObject(from: requestJSON),
              let url = ollamaURL(path: body["messages"] == nil ? "/api/generate" : "/api/chat") else {
            return [:]
        }

        var payload: [String: Any] = [
            "model": model,
            "stream": false
        ]
        if let messages = body["messages"] {
            payload["messages"] = messages
        } else {
            payload["prompt"] = body["prompt"] as? String ?? ""
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let startedAt = Date()
        guard case let .success((data, response)) = synchronousDataRequest(request),
              200..<300 ~= response.statusCode,
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        let responseText = ((result["message"] as? [String: Any])?["content"] as? String)
            ?? (result["response"] as? String)
            ?? ""
        let durationNs = (result["total_duration"] as? NSNumber)?.int64Value ?? 0

        return [
            "response": responseText,
            "inference_time_ms": durationNs > 0 ? durationNs / 1_000_000 : Int(Date().timeIntervalSince(startedAt) * 1000),
            "backend": "ollama",
            "prompt_eval_count": (result["prompt_eval_count"] as? NSNumber)?.intValue ?? 0,
            "eval_count": (result["eval_count"] as? NSNumber)?.intValue ?? 0
        ]
    }

    // MARK: - HF Cloud

    func hfCloudInfer(modelId: String, requestJSON: String) -> [String: Any] {
        guard !hfToken.isEmpty else {
            return [
                "error": "auth_required",
                "message": "HF cloud inference requires a token."
            ]
        }

        guard let requestObject = jsonObject(from: requestJSON) else {
            return [:]
        }

        var body = buildHFRequestBody(from: requestObject)
        if body.isEmpty {
            body["inputs"] = ""
        }

        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://api-inference.huggingface.co/models/\(modelId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(hfToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let startedAt = Date()
        guard case let .success((data, response)) = synchronousDataRequest(request) else {
            return [
                "error": "network",
                "message": "Connection to HF Inference API failed"
            ]
        }

        if response.statusCode == 401 || response.statusCode == 403 {
            return [
                "error": "auth_required",
                "message": "Hugging Face rejected your token."
            ]
        }

        if response.statusCode == 503 {
            let payload = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let estimated = (payload["estimated_time"] as? NSNumber)?.intValue
            var message = "Model is loading, try again in a moment."
            if let estimated {
                message += " Estimated: \(estimated)s"
            }
            return [
                "error": "model_loading",
                "message": message
            ]
        }

        guard response.statusCode == 200 else {
            let bodySnippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
            return [
                "error": "http",
                "message": "HTTP \(response.statusCode): \(bodySnippet)"
            ]
        }

        let payload = try? JSONSerialization.jsonObject(with: data)
        let responseText: String
        if let array = payload as? [[String: Any]],
           let first = array.first,
           let generated = first["generated_text"] as? String {
            responseText = generated
        } else if let dict = payload as? [String: Any],
                  let generated = dict["generated_text"] as? String {
            responseText = generated
        } else {
            responseText = String(data: data, encoding: .utf8) ?? ""
        }

        return [
            "response": responseText,
            "inference_time_ms": Int(Date().timeIntervalSince(startedAt) * 1000),
            "backend": "hf_cloud",
            "model_id": modelId
        ]
    }

    // MARK: - Private

    private func string(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
        guard let ptr else { return "" }
        defer { kelpie_ai_free_string(ptr) }
        return String(cString: ptr)
    }

    private func modelDirectoryURL(for id: String) -> URL {
        modelsDirectoryURL.appendingPathComponent(id, isDirectory: true)
    }

    private func modelFileURL(for id: String) -> URL {
        modelDirectoryURL(for: id).appendingPathComponent("model.gguf")
    }

    private func writeMetadata(for model: AIApprovedModel, to directoryURL: URL) {
        let metadata: [String: Any] = [
            "id": model.id,
            "name": model.name,
            "huggingFaceRepo": model.huggingFaceRepo,
            "huggingFaceFile": model.huggingFaceFile,
            "sizeBytes": model.sizeBytes,
            "ramWhenLoadedGB": model.ramWhenLoadedGB,
            "capabilities": model.capabilities,
            "memory": model.memory,
            "minRamGB": model.minRamGB,
            "recommendedRamGB": model.recommendedRamGB,
            "quantization": model.quantization,
            "contextWindow": model.contextWindow,
            "downloaded_at": ISO8601DateFormatter().string(from: Date())
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted]) else {
            return
        }
        try? data.write(to: directoryURL.appendingPathComponent("metadata.json"), options: .atomic)
    }

    private func downloadHTTPError(for response: HTTPURLResponse, tokenIsSet: Bool) -> String? {
        if response.statusCode == 401 || response.statusCode == 403 {
            return errorJSONString(
                code: "auth_required",
                message: tokenIsSet
                    ? "Hugging Face rejected your token. Check it on the settings page."
                    : "This model requires a Hugging Face token. Set one in the Models tab."
            )
        }

        guard response.statusCode == 200 else {
            return errorJSONString(
                code: "http",
                message: "HTTP \(response.statusCode)"
            )
        }

        return nil
    }

    private func finalizeDownloadedModel(
        from location: URL,
        model: AIApprovedModel,
        directoryURL: URL,
        temporaryURL: URL,
        finalURL: URL
    ) -> String? {
        do {
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: location, to: temporaryURL)
        } catch {
            return errorJSONString(
                code: "filesystem",
                message: "Cannot create download file"
            )
        }

        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        let fileSize = (fileAttributes?[.size] as? NSNumber)?.int64Value ?? 0
        if fileSize < 1_000_000 {
            let snippet = (try? Data(contentsOf: temporaryURL))
                .flatMap { data in
                    String(data: data.prefix(200), encoding: .utf8)
                } ?? ""
            try? FileManager.default.removeItem(at: temporaryURL)

            if snippet.contains("Invalid")
                || snippet.contains("Access")
                || snippet.contains("login")
                || snippet.contains("<!DOCTYPE") {
                return errorJSONString(
                    code: "auth_required",
                    message: "Download failed — Hugging Face returned an auth error."
                )
            }

            return errorJSONString(
                code: "validation",
                message: "Downloaded file is too small (\(fileSize) bytes)"
            )
        }

        do {
            try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            return errorJSONString(
                code: "filesystem",
                message: "Failed to finalize download"
            )
        }

        writeMetadata(for: model, to: directoryURL)
        return nil
    }

    private func errorJSONString(code: String, message: String) -> String {
        let object = [
            "error": code,
            "message": message
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return message
        }
        return string
    }

    private func normalizeOllamaEndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "http://localhost:11434"
        }

        if let url = URL(string: trimmed),
           let host = url.host {
            let port = url.port ?? 11434
            return "http://\(host):\(port)"
        }

        if let url = URL(string: "http://\(trimmed)"),
           let host = url.host {
            let port = url.port ?? 11434
            return "http://\(host):\(port)"
        }

        return "http://localhost:11434"
    }

    private func ollamaURL(path: String) -> URL? {
        URL(string: ollamaEndpoint)?.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func synchronousDataRequest(_ request: URLRequest) -> Result<(Data, HTTPURLResponse), Error> {
        let session = URLSession(configuration: .ephemeral)
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, HTTPURLResponse), Error>?

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            guard let data, let http = response as? HTTPURLResponse else {
                result = .failure(NSError(domain: "AIManager", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid HTTP response"
                ]))
                return
            }
            result = .success((data, http))
        }
        task.resume()
        semaphore.wait()
        session.finishTasksAndInvalidate()
        return result ?? .failure(NSError(domain: "AIManager", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Request did not complete"
        ]))
    }

    private func synchronousDownload(_ request: URLRequest) -> Result<(URL, HTTPURLResponse), Error> {
        let session = URLSession(configuration: .ephemeral)
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(URL, HTTPURLResponse), Error>?

        let task = session.downloadTask(with: request) { url, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            guard let url, let http = response as? HTTPURLResponse else {
                result = .failure(NSError(domain: "AIManager", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid download response"
                ]))
                return
            }
            result = .success((url, http))
        }
        task.resume()
        semaphore.wait()
        session.finishTasksAndInvalidate()
        return result ?? .failure(NSError(domain: "AIManager", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "Download did not complete"
        ]))
    }

    private func jsonObject(from string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func buildHFRequestBody(from request: [String: Any]) -> [String: Any] {
        if request["inputs"] != nil {
            return request
        }

        if let prompt = request["prompt"] as? String {
            var body: [String: Any] = [
                "inputs": prompt,
                "parameters": [
                    "max_new_tokens": (request["max_tokens"] as? NSNumber)?.intValue ?? 512
                ]
            ]
            if let temperature = request["temperature"] {
                var parameters = body["parameters"] as? [String: Any] ?? [:]
                parameters["temperature"] = temperature
                body["parameters"] = parameters
            }
            return body
        }

        if let messages = request["messages"] as? [[String: Any]] {
            let prompt = messages.reduce(into: "") { partialResult, message in
                let role = message["role"] as? String ?? "user"
                let content = message["content"] as? String ?? ""
                switch role {
                case "system":
                    partialResult += content + "\n\n"
                case "assistant":
                    partialResult += "Assistant: \(content)\n"
                default:
                    partialResult += "User: \(content)\n"
                }
            } + "Assistant: "

            var body: [String: Any] = [
                "inputs": prompt,
                "parameters": [
                    "max_new_tokens": (request["max_tokens"] as? NSNumber)?.intValue ?? 512
                ]
            ]
            if let temperature = request["temperature"] {
                var parameters = body["parameters"] as? [String: Any] ?? [:]
                parameters["temperature"] = temperature
                body["parameters"] = parameters
            }
            return body
        }

        return [:]
    }

    private static func ollamaCapabilities(for model: String) -> [String] {
        let lowercased = model.lowercased()
        if lowercased.contains("llava")
            || lowercased.contains("bakllava")
            || lowercased.contains("moondream")
            || lowercased.contains("gemma") {
            return ["text", "vision"]
        }
        return ["text"]
    }
}
