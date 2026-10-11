import Foundation
import AppKit

// MARK: - Inference dispatch + native-model resolution
//
// The `infer` request handler, native GGUF model resolution, and the
// context-preload helpers it relies on. Ollama-specific transport lives in
// AIHandler+Ollama.swift; small response/error mappers stay in AIHandler.swift.

extension AIHandler {

    // swiftlint:disable:next function_body_length
    func infer(_ body: [String: Any]) async -> [String: Any] {
        let backendState = await backendStore.snapshot()
        let nativeLoaded = await MainActor.run { engine.isLoaded }
        if !nativeLoaded, backendState.backend != "ollama", await openAIService.activeEndpoint() != nil {
            return await inferWithOpenAI(body)
        }
        guard nativeLoaded || backendState.backend == "ollama" else {
            return errorResponse(code: "NO_MODEL_LOADED", message: "Load a model first with ai-load")
        }

        let tabId = HandlerContext.tabId(from: body)
        let maxTokens = body["maxTokens"] as? Int ?? 512
        let temperature = body["temperature"] as? Double ?? 0.7
        let prompt = body["prompt"] as? String ?? ""
        let contextMode = body["context"] as? String
        let audio = decodeBase64Field(body["audio"])
        if let messages = body["messages"] as? [[String: Any]] {
            return await inferLocalChat(body, history: messages, backend: backendState)
        }

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
                let image = contextMode == "screenshot" ? try await screenshotData(tabId: tabId) : nil
                let contextText = try await inferenceContext(body, tabId: tabId)
                let result = try await inferWithOllama(
                    endpoint: backendState.ollamaEndpoint ?? defaultOllamaEndpoint,
                    model: model,
                    prompt: prompt,
                    messages: nil,
                    contextText: contextText,
                    image: image
                )
                return successResponse([
                    "response": result.text,
                    "tokensUsed": result.tokensUsed,
                    "inferenceTimeMs": result.inferenceTimeMs
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
                let image = try await screenshotData(tabId: tabId)
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
                    "inferenceTimeMs": result.inferenceTimeMs
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
            let preloaded = try await inferenceContext(body, tabId: tabId)
            let harness = InferenceHarness(context: context, router: router)
            let result = try await harness.run(prompt: prompt, audio: audio, preloadedContext: preloaded)

            var response = successResponse([
                "response": result.answer,
                "tokensUsed": result.totalTokens,
                "inferenceTimeMs": result.totalTimeMs
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

    func resolveNativeModel(from body: [String: Any]) -> NativeModelResolution {
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
            .appendingPathComponent(".kelpie/models/\(model)/model.gguf")
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
    func inferenceContext(_ body: [String: Any], tabId: String?) async throws -> String? {
        if let text = body["text"] as? String { return text }
        return try await preloadedContext(mode: body["context"] as? String, tabId: tabId)
    }

    @MainActor
    func preloadedContext(mode: String?, tabId: String?) async throws -> String? {
        guard mode != nil && mode != "screenshot" else { return nil }
        guard ["page_text", "dom", "accessibility"].contains(mode ?? "") else {
            throw NSError(domain: "AIPageContext", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported page context mode"])
        }
        let page = try await commonPageContext(tabId: tabId)
        let data = try JSONSerialization.data(withJSONObject: page.pageTextPayload, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)
    }

    @MainActor
    func commonPageContext(tabId: String?) async throws -> AIPageContext {
        guard let router else {
            throw NSError(domain: "AIPageContext", code: 1, userInfo: [NSLocalizedDescriptionKey: "Browser router is unavailable"])
        }
        return try AIPageContext(observation: await router.pageObservation(tabId: tabId))
    }

    @MainActor
    func screenshotData(tabId: String?) async throws -> Data {
        let image = try await context.takeSnapshot(tabId: tabId)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "AIHandler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode screenshot"])
        }
        return png
    }

    func buildNativeSingleShotPrompt(prompt: String, extraContext: String?) -> String {
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

    func parseResponseJSON(_ text: String) -> (answer: String, transcription: String?) {
        guard let start = text.firstIndex(of: "{") else { return (text, nil) }
        var depth = 0
        var end: String.Index?
        for index in text.indices[start...] {
            switch text[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { end = index; break }
            default: break
            }
            if end != nil { break }
        }
        guard let end,
              let data = String(text[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (text, nil)
        }
        return (
            object["answer"] as? String ?? object["response"] as? String ?? text,
            object["transcription"] as? String
        )
    }

    func approximateTokens(for text: String) -> Int {
        max(1, text.count / 4)
    }
}
