import Foundation

// MARK: - Ollama transport
//
// HTTP integration for the Ollama backend: chat/generate request shaping,
// reachability probe, URL building, and capability inference. These are the
// only call sites that talk to an external Ollama server.

extension AIHandler {

    func inferWithOllamaAgentLoop(
        endpoint: String,
        model: String,
        prompt: String,
        historyMessages: [[String: Any]],
        image: Data?
    ) async throws -> InferenceEngine.InferenceResult {
        let startedAt = DispatchTime.now()
        let harness = InferenceHarness(context: context)
        let url = try ollamaURL(endpoint: endpoint, path: "/api/chat")

        // Pre-fetch page text — fast JS call, works with every model
        let pageText = await harness.executeTool("get_text", args: [:])
        let summary = await PageSummary.gather(from: context)
        let systemContent = """
        You are a browser assistant built into Kelpie. Answer questions about the current web page.
        Be concise. Only state facts present in the page content below. Never guess or make up content.

        Page: "\(summary.title)"
        URL: \(summary.url)

        Page content:
        \(pageText)
        """
        let systemMessage: [String: Any] = ["role": "system", "content": systemContent]
        var messages: [[String: Any]] = [systemMessage] + historyMessages
        var userMessage: [String: Any] = ["role": "user", "content": prompt]
        if let image {
            userMessage["images"] = [image.base64EncodedString()]
        }
        messages.append(userMessage)

        let payload: [String: Any] = ["model": model, "messages": messages, "stream": false]
        let response = try await postJSON(url: url, payload: payload)
        let content = ((response["message"] as? [String: Any])?["content"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let totalTokens = response["eval_count"] as? Int ?? approximateTokens(for: content)
        return InferenceEngine.InferenceResult(
            text: content.isEmpty ? "No response." : content,
            tokensUsed: totalTokens,
            inferenceTimeMs: parseDurationMs(response["total_duration"]) ?? elapsedMs(since: startedAt)
        )
    }

    func inferWithOllama(
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
                "stream": false
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
            "stream": false
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

    func postJSON(url: URL, payload: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 300

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "AIHandler", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Lost connection to Ollama during inference"
            ])
        }

        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func isOllamaReachable(endpoint: String) async -> Bool {
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

    func ollamaURL(endpoint: String, path: String) throws -> URL {
        guard let base = URL(string: endpoint) else {
            throw NSError(domain: "AIHandler", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid Ollama endpoint"])
        }
        return base.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    func ollamaCapabilities(for model: String) -> [String] {
        let lowercased = model.lowercased()
        if lowercased.contains("llava") || lowercased.contains("bakllava") || lowercased.contains("moondream") {
            return ["text", "vision"]
        }
        return ["text"]
    }

    func merge(prompt: String, contextText: String?) -> String {
        guard let contextText, !contextText.isEmpty else { return prompt }
        return """
        \(prompt)

        Context:
        \(contextText)
        """
    }

    func parseDurationMs(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue > 1_000_000 ? intValue / 1_000_000 : intValue
        }
        if let doubleValue = value as? Double {
            return doubleValue > 1_000_000 ? Int(doubleValue / 1_000_000.0) : Int(doubleValue)
        }
        return nil
    }
}
