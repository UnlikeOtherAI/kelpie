import Foundation

extension AIHandler {
    /// Local panel chat shares one tab snapshot and the caller's full history.
    func inferLocalChat(
        _ body: [String: Any], history: [[String: Any]], backend: AIBackendStore.Snapshot
    ) async -> [String: Any] {
        let tabId: String?
        if body["text"] is String && body["context"] as? String != "screenshot" {
            tabId = HandlerContext.tabId(from: body)
        } else {
            switch await pinTab(requested: HandlerContext.tabId(from: body)) {
            case .pinned(let pinned): tabId = pinned
            case .rejected(let response): return response
            }
        }
        let page: AIPageContext
        do {
            page = try await localChatPage(body, tabId: tabId)
        } catch {
            return errorResponse(code: "PAGE_CONTEXT_UNAVAILABLE", message: "Could not read this tab: \(error.localizedDescription)")
        }
        do {
            let image = body["context"] as? String == "screenshot" ? try await screenshotData(tabId: tabId) : nil
            let result = try await runLocalChat(body, history: history, backend: backend, page: page, image: image)
            return successResponse([
                "response": result.text, "tokensUsed": result.tokensUsed, "inferenceTimeMs": result.inferenceTimeMs
            ])
        } catch let error as InferenceEngine.InferenceError {
            return mapInferenceError(error)
        } catch {
            let code = backend.backend == "ollama" ? "OLLAMA_DISCONNECTED" : "INFERENCE_FAILED"
            return errorResponse(code: code, message: error.localizedDescription)
        }
    }

    func localChatPage(_ body: [String: Any], tabId: String?) async throws -> AIPageContext {
        if let text = body["text"] as? String { return AIPageContext(suppliedText: text) }
        if let mode = body["context"] as? String, mode == "dom" || mode == "accessibility" {
            guard let text = await preloadedContext(mode: mode, tabId: tabId), !text.isEmpty else {
                throw NSError(domain: "AIPageContext", code: 1, userInfo: [NSLocalizedDescriptionKey: "Page extraction failed."])
            }
            return AIPageContext(suppliedText: text)
        }
        return try await AIPageContext.gather(from: context, tabId: tabId)
    }

    private func runLocalChat(
        _ body: [String: Any], history: [[String: Any]], backend: AIBackendStore.Snapshot, page: AIPageContext, image: Data?
    ) async throws -> InferenceEngine.InferenceResult {
        let prompt = body["prompt"] as? String ?? ""
        let audio = decodeBase64Field(body["audio"])
        if backend.backend == "ollama" {
            guard audio == nil else { throw InferenceEngine.InferenceError.audioNotSupported }
            guard let model = backend.model else { throw InferenceEngine.InferenceError.noModelLoaded }
            return try await inferWithOllamaAgentLoop(
                endpoint: backend.ollamaEndpoint ?? defaultOllamaEndpoint,
                model: model,
                prompt: prompt,
                historyMessages: history,
                image: image,
                page: page
            )
        }
        return try await engine.infer(
            prompt: page.nativePrompt(prompt: prompt, history: history),
            audio: audio,
            image: image,
            maxTokens: body["maxTokens"] as? Int ?? 512,
            temperature: Float(body["temperature"] as? Double ?? 0.7)
        )
    }
}
