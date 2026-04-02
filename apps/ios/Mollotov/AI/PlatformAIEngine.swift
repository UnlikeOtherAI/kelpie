import Foundation

struct PlatformAIEngine {
    static var isAvailable: Bool {
        if #available(iOS 26, *) {
            // Will use: SystemLanguageModel.isAvailable
            return true
        }
        return false
    }

    func infer(prompt: String) async throws -> String {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.emptyPrompt
        }

        if #available(iOS 26, *) {
            // TODO: Use FoundationModels.SystemLanguageModel when the iOS 26 SDK is available.
            throw AIError.platformUnavailable
        }

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
                return "Platform AI is not yet wired on iOS"
            }
        }
    }
}
