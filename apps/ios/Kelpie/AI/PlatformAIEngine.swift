import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct PlatformAIEngine {
    static var isAvailable: Bool {
#if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
#endif
        return false
    }

    func infer(prompt: String) async throws -> String {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.emptyPrompt
        }

#if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return try await SystemLanguageModel.default.generateResponse(to: prompt)
        }
#endif
        throw AIError.platformUnavailable
    }

    enum AIError: LocalizedError {
        case emptyPrompt
        case platformUnavailable

        var errorDescription: String? {
            switch self {
            case .emptyPrompt:
                return "prompt is required"
            case .platformUnavailable:
                return "Platform AI is unavailable on this device"
            }
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
private extension SystemLanguageModel {
    func generateResponse(to prompt: String) async throws -> String {
        let session = LanguageModelSession(model: self)
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
#endif
